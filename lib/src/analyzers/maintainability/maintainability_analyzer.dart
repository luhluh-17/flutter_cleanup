import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../analysis/analysis_result.dart';
import '../../analysis/analyzer.dart';
import '../../analysis/path_utils.dart';
import '../../models/finding.dart';
import '../../models/project_paths.dart';
import '../../services/ignore_service.dart';
import 'maintainability_config.dart';
import 'models/maintainability_issue.dart';
import 'utils/nesting_depth_calculator.dart';

/// Flags maintainability smells in non-generated Dart files under `lib/`.
///
/// Five metrics are measured against configurable thresholds
/// ([MaintainabilityConfig]):
/// 1. file length (non-empty source lines),
/// 2. method length (any `FunctionDeclaration`/`MethodDeclaration` except
///    getters, setters, constructors and `build`),
/// 3. `build()` method length,
/// 4. widget classes per file, and
/// 5. maximum widget-tree nesting depth.
///
/// Each file is parsed exactly once and all five rules run over that single
/// [CompilationUnit], so the analyzer scales to large projects. Analysis is
/// purely syntactic (no element resolution) — widget detection and nesting are
/// practical AST approximations, consistent with [DuplicateWidgetsAnalyzer].
class MaintainabilityAnalyzer implements Analyzer {
  const MaintainabilityAnalyzer();

  static const String rule = MaintainabilityIssue.rule;

  /// Widget base classes that make a [ClassDeclaration] count as a widget.
  static const Set<String> _widgetSuperclasses = {
    'StatelessWidget',
    'StatefulWidget',
    'ConsumerWidget',
    'HookWidget',
    'HookConsumerWidget',
    'ConsumerStatefulWidget',
  };

  /// Generated-file suffixes skipped in addition to [IgnoreService] patterns.
  /// Covers the spec's full list, including `*.config.dart`/`*.pbserver.dart`
  /// that the shared defaults don't carry.
  static const List<String> _generatedSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.config.dart',
    '.mocks.dart',
    '.pb.dart',
    '.pbenum.dart',
    '.pbjson.dart',
    '.pbserver.dart',
  ];

  @override
  String get name => 'maintainability';

  @override
  Future<AnalysisResult> analyze(ProjectPaths paths) async {
    final config = MaintainabilityConfig.forProject(paths.root);
    if (!config.enabled) return AnalysisResult.empty(name);

    final libDir = Directory(paths.libDir);
    if (!libDir.existsSync()) return AnalysisResult.empty(name);

    final ignore = IgnoreService.forProject(paths.root);

    final findings = <Finding>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.dart') continue;
      final relPath = toPosixRelative(paths.root, entity.path);
      if (ignore.isIgnored(relPath) || _isGenerated(relPath)) continue;

      final String source;
      try {
        source = entity.readAsStringSync();
      } on FileSystemException {
        continue;
      }

      for (final issue in _analyzeFile(source, config)) {
        findings.add(issue.toFinding(relPath));
      }
    }

    // Deterministic output: by path, then by line (file-level findings first).
    findings.sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      if (byPath != 0) return byPath;
      return (a.line ?? 0).compareTo(b.line ?? 0);
    });

    return AnalysisResult(analyzerName: name, findings: findings);
  }

  /// Parses [source] once and collects every maintainability issue in it.
  List<MaintainabilityIssue> _analyzeFile(
      String source, MaintainabilityConfig config) {
    final CompilationUnit unit;
    final LineInfo lineInfo;
    try {
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      unit = parsed.unit;
      lineInfo = parsed.lineInfo;
    } catch (_) {
      return const []; // Unparseable file — skip rather than abort the run.
    }

    final issues = <MaintainabilityIssue>[];

    // Rule 1: file length (non-empty source lines).
    _addIfOverThreshold(
      issues,
      kind: MaintainabilityIssueKind.fileLength,
      value: _nonEmptyLineCount(source),
      threshold: config.fileLines,
    );

    // Rules 2–5 walk the single parsed unit.
    final visitor = _FileVisitor(lineInfo, config);
    unit.accept(visitor);
    issues.addAll(visitor.issues);

    // Rule 4: widget count (file-level).
    _addIfOverThreshold(
      issues,
      kind: MaintainabilityIssueKind.widgetCount,
      value: visitor.widgetClassCount,
      threshold: config.widgetCount,
    );

    // Rule 5: maximum widget nesting depth across all build() bodies.
    _addIfOverThreshold(
      issues,
      kind: MaintainabilityIssueKind.nestingDepth,
      value: visitor.maxNestingDepth,
      threshold: config.widgetNestingDepth,
      line: visitor.maxNestingLine,
    );

    return issues;
  }

  /// Appends a [kind] issue when [value] crosses [threshold]'s warning/error
  /// bound; below warning produces nothing.
  static void _addIfOverThreshold(
    List<MaintainabilityIssue> issues, {
    required MaintainabilityIssueKind kind,
    required int value,
    required Threshold threshold,
    String? subject,
    int? line,
  }) {
    final severity = severityFor(value, threshold);
    if (severity == null) return;
    issues.add(MaintainabilityIssue(
      kind: kind,
      severity: severity,
      value: value,
      subject: subject,
      line: line,
    ));
  }

  /// Maps a measured [value] to a severity, or null when below the warning bound.
  static Severity? severityFor(int value, Threshold threshold) {
    if (value >= threshold.error) return Severity.error;
    if (value >= threshold.warning) return Severity.warning;
    return null;
  }

  static int _nonEmptyLineCount(String source) {
    var count = 0;
    for (final line in source.split('\n')) {
      if (line.trim().isNotEmpty) count++;
    }
    return count;
  }

  static bool _isGenerated(String relPath) =>
      _generatedSuffixes.any(relPath.endsWith);
}

/// Walks a parsed file, emitting method/build issues and accumulating the
/// file-level widget count and maximum nesting depth in one pass.
class _FileVisitor extends RecursiveAstVisitor<void> {
  _FileVisitor(this._lineInfo, this._config);

  final LineInfo _lineInfo;
  final MaintainabilityConfig _config;
  static const NestingDepthCalculator _nesting = NestingDepthCalculator();

  final List<MaintainabilityIssue> issues = [];
  int widgetClassCount = 0;
  int maxNestingDepth = 0;
  int? maxNestingLine;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superName = node.extendsClause?.superclass.name.lexeme;
    if (superName != null &&
        MaintainabilityAnalyzer._widgetSuperclasses.contains(superName)) {
      widgetClassCount++;
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.isGetter || node.isSetter) {
      super.visitMethodDeclaration(node);
      return;
    }

    if (_isBuildMethod(node)) {
      // Rule 3: build() body length.
      MaintainabilityAnalyzer._addIfOverThreshold(
        issues,
        kind: MaintainabilityIssueKind.buildMethodLength,
        value: _lineSpan(node.body),
        threshold: _config.buildMethodLines,
        line: _lineOf(node.offset),
      );
      // Rule 5: nesting depth of this build() body.
      final depth = _nesting.maxDepth(node.body);
      if (depth > maxNestingDepth) {
        maxNestingDepth = depth;
        maxNestingLine = _lineOf(node.offset);
      }
    } else {
      // Rule 2: method length.
      MaintainabilityAnalyzer._addIfOverThreshold(
        issues,
        kind: MaintainabilityIssueKind.methodLength,
        value: _lineSpan(node),
        threshold: _config.methodLines,
        subject: node.name.lexeme,
        line: _lineOf(node.offset),
      );
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (!node.isGetter && !node.isSetter) {
      // Rule 2: top-level / local function length.
      MaintainabilityAnalyzer._addIfOverThreshold(
        issues,
        kind: MaintainabilityIssueKind.methodLength,
        value: _lineSpan(node),
        threshold: _config.methodLines,
        subject: node.name.lexeme,
        line: _lineOf(node.offset),
      );
    }
    super.visitFunctionDeclaration(node);
  }

  /// A `Widget build(BuildContext context)` method: named `build` with a single
  /// `BuildContext` parameter. The parameter type is checked via source text to
  /// stay independent of analyzer AST class churn (no element resolution).
  bool _isBuildMethod(MethodDeclaration node) {
    if (node.name.lexeme != 'build') return false;
    final params = node.parameters?.parameters;
    if (params == null || params.length != 1) return false;
    return params.single.toSource().contains('BuildContext');
  }

  /// Inclusive source-line span of [node].
  int _lineSpan(AstNode node) =>
      _lineOf(node.end) - _lineOf(node.offset) + 1;

  int _lineOf(int offset) => _lineInfo.getLocation(offset).lineNumber;
}
