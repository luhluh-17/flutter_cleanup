import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
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
/// Every metric is measured against a single accepted maximum
/// ([MaintainabilityConfig]); a value *strictly greater than* the limit is
/// reported as a `warning`:
/// 1. file length — lines of code, with the applicable limit chosen by
///    classifying the file as a controller, a widget file, or a generic file,
/// 2. method length (any `FunctionDeclaration`/`MethodDeclaration` except
///    getters, setters, constructors and `build`),
/// 3. `build()` method length,
/// 4. maximum widget-tree nesting depth,
/// 5. public top-level class count per file,
/// 6. constructor parameter count, and
/// 7. Dart files directly inside each folder under `lib/`.
///
/// Each file is parsed exactly once and all per-file rules run over that single
/// [CompilationUnit], so the analyzer scales to large projects. Analysis is
/// purely syntactic (no element resolution) — widget/controller detection and
/// nesting are practical AST approximations, consistent with
/// [DuplicateWidgetsAnalyzer].
class MaintainabilityAnalyzer implements Analyzer {
  const MaintainabilityAnalyzer();

  /// Widget base classes that make a [ClassDeclaration] count as a widget (and
  /// its file a "widget file").
  static const Set<String> _widgetSuperclasses = {
    'StatelessWidget',
    'StatefulWidget',
    'ConsumerWidget',
    'HookWidget',
    'HookConsumerWidget',
    'ConsumerStatefulWidget',
  };

  /// Base classes that make a [ClassDeclaration] count as a controller (and its
  /// file a "controller"). A class whose name ends in `Controller`, or a file
  /// named `*_controller.dart`, also classifies as a controller.
  static const Set<String> _controllerSuperclasses = {
    'ChangeNotifier',
    'StateNotifier',
    'Notifier',
    'AsyncNotifier',
    'AutoDisposeNotifier',
    'AutoDisposeAsyncNotifier',
    'GetxController',
    'Cubit',
    'Bloc',
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
    // Dart files that pass the ignore/generated filters, counted per parent
    // folder for the folder-size rule.
    final folderFileCounts = <String, int>{};

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.dart') continue;
      final relPath = toPosixRelative(paths.root, entity.path);
      if (ignore.isIgnored(relPath) || _isGenerated(relPath)) continue;

      final folder = p.url.dirname(relPath);
      folderFileCounts[folder] = (folderFileCounts[folder] ?? 0) + 1;

      final String source;
      try {
        source = entity.readAsStringSync();
      } on FileSystemException {
        continue;
      }

      for (final issue in _analyzeFile(source, relPath, config)) {
        findings.add(issue.toFinding(relPath));
      }
    }

    // Folder-size rule (analyzer level, not AST).
    folderFileCounts.forEach((folder, count) {
      if (count > config.folderFiles) {
        findings.add(MaintainabilityIssue(
          kind: MaintainabilityIssueKind.folderFileCount,
          value: count,
          limit: config.folderFiles,
        ).toFinding(folder));
      }
    });

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
      String source, String relPath, MaintainabilityConfig config) {
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

    // Rules 2–6 walk the single parsed unit.
    final visitor = _FileVisitor(lineInfo, config);
    unit.accept(visitor);
    issues.addAll(visitor.issues);

    // Rule 1: file length. The limit and issue kind depend on how the file is
    // classified from the classes it declares (and its name).
    final fileClass = visitor.classify(relPath);
    _addIfOverLimit(
      issues,
      kind: fileClass.kind,
      value: _codeLineCount(unit, lineInfo),
      limit: fileClass.limit(config),
    );

    // Rule 4: maximum widget nesting depth across all build() bodies.
    _addIfOverLimit(
      issues,
      kind: MaintainabilityIssueKind.nestingDepth,
      value: visitor.maxNestingDepth,
      limit: config.widgetNestingDepth,
      line: visitor.maxNestingLine,
    );

    // Rule 5: public top-level class count (file-level).
    _addIfOverLimit(
      issues,
      kind: MaintainabilityIssueKind.publicClassCount,
      value: visitor.publicClassCount,
      limit: config.maxPublicClasses,
    );

    return issues;
  }

  /// Appends a [kind] issue when [value] is strictly greater than [limit].
  static void _addIfOverLimit(
    List<MaintainabilityIssue> issues, {
    required MaintainabilityIssueKind kind,
    required int value,
    required int limit,
    String? subject,
    int? line,
  }) {
    if (value <= limit) return;
    issues.add(MaintainabilityIssue(
      kind: kind,
      value: value,
      limit: limit,
      subject: subject,
      line: line,
    ));
  }

  /// Counts distinct source lines that contain at least one real code token.
  ///
  /// Dart comments are attached to tokens as `precedingComments` and are not
  /// part of the main token chain, so iterating [unit]'s tokens naturally
  /// excludes comment-only lines; blank lines carry no token and are excluded
  /// too. A line with code followed by a trailing comment still counts. Tokens
  /// spanning multiple lines (e.g. multi-line strings) mark every line covered.
  static int _codeLineCount(CompilationUnit unit, LineInfo lineInfo) {
    final lines = <int>{};
    Token? token = unit.beginToken;
    while (token != null && token.type != TokenType.EOF) {
      final start = lineInfo.getLocation(token.offset).lineNumber;
      final end = lineInfo.getLocation(token.end).lineNumber;
      for (var l = start; l <= end; l++) {
        lines.add(l);
      }
      final next = token.next;
      if (next == null || next == token) break;
      token = next;
    }
    return lines.length;
  }

  static bool _isGenerated(String relPath) =>
      _generatedSuffixes.any(relPath.endsWith);
}

/// How a file's overall line-length limit is chosen. Precedence is
/// controller → widget → generic file.
enum _FileClass {
  controller(MaintainabilityIssueKind.controllerLength),
  widget(MaintainabilityIssueKind.widgetFileLength),
  other(MaintainabilityIssueKind.fileLength);

  const _FileClass(this.kind);

  final MaintainabilityIssueKind kind;

  int limit(MaintainabilityConfig config) {
    switch (this) {
      case _FileClass.controller:
        return config.controllerLines;
      case _FileClass.widget:
        return config.widgetFileLines;
      case _FileClass.other:
        return config.fileLines;
    }
  }
}

/// Walks a parsed file, emitting method/build/constructor issues and
/// accumulating file-level signals (widget/controller detection, public-class
/// count, maximum nesting depth) in one pass.
class _FileVisitor extends RecursiveAstVisitor<void> {
  _FileVisitor(this._lineInfo, this._config);

  final LineInfo _lineInfo;
  final MaintainabilityConfig _config;
  static const NestingDepthCalculator _nesting = NestingDepthCalculator();

  final List<MaintainabilityIssue> issues = [];
  int publicClassCount = 0;
  int maxNestingDepth = 0;
  int? maxNestingLine;
  bool _hasWidgetClass = false;
  bool _hasControllerClass = false;

  /// Classifies the whole file (for the file-length rule) from the classes seen
  /// during the walk plus its [relPath]. Precedence: controller → widget →
  /// generic file.
  _FileClass classify(String relPath) {
    final fileName = p.url.basename(relPath);
    if (_hasControllerClass || fileName.endsWith('_controller.dart')) {
      return _FileClass.controller;
    }
    if (_hasWidgetClass) return _FileClass.widget;
    return _FileClass.other;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.namePart.typeName.lexeme;
    if (!className.startsWith('_')) publicClassCount++;

    final superName = node.extendsClause?.superclass.name.lexeme;
    if (superName != null &&
        MaintainabilityAnalyzer._widgetSuperclasses.contains(superName)) {
      _hasWidgetClass = true;
    }
    if (className.endsWith('Controller') ||
        (superName != null &&
            MaintainabilityAnalyzer._controllerSuperclasses
                .contains(superName))) {
      _hasControllerClass = true;
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    // Rule 6: constructor parameter count.
    final count = node.parameters.parameters.length;
    final owner =
        node.thisOrAncestorOfType<ClassDeclaration>()?.namePart.typeName.lexeme ??
            node.typeName?.name ??
            '<constructor>';
    final label = node.name == null ? owner : '$owner.${node.name!.lexeme}';
    MaintainabilityAnalyzer._addIfOverLimit(
      issues,
      kind: MaintainabilityIssueKind.constructorParams,
      value: count,
      limit: _config.constructorParams,
      subject: label,
      line: _lineOf(node.offset),
    );
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.isGetter || node.isSetter) {
      super.visitMethodDeclaration(node);
      return;
    }

    if (_isBuildMethod(node)) {
      // Rule 3: build() body length.
      MaintainabilityAnalyzer._addIfOverLimit(
        issues,
        kind: MaintainabilityIssueKind.buildMethodLength,
        value: _lineSpan(node.body),
        limit: _config.buildMethodLines,
        line: _lineOf(node.offset),
      );
      // Rule 4: nesting depth of this build() body.
      final depth = _nesting.maxDepth(node.body);
      if (depth > maxNestingDepth) {
        maxNestingDepth = depth;
        maxNestingLine = _lineOf(node.offset);
      }
    } else {
      // Rule 2: method length.
      MaintainabilityAnalyzer._addIfOverLimit(
        issues,
        kind: MaintainabilityIssueKind.methodLength,
        value: _lineSpan(node),
        limit: _config.methodLines,
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
      MaintainabilityAnalyzer._addIfOverLimit(
        issues,
        kind: MaintainabilityIssueKind.methodLength,
        value: _lineSpan(node),
        limit: _config.methodLines,
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
  int _lineSpan(AstNode node) => _lineOf(node.end) - _lineOf(node.offset) + 1;

  int _lineOf(int offset) => _lineInfo.getLocation(offset).lineNumber;
}
