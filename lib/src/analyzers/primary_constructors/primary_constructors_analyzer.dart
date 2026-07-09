import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../analysis/analysis_result.dart';
import '../../analysis/analyzer.dart';
import '../../analysis/path_utils.dart';
import '../../models/finding.dart';
import '../../models/project_paths.dart';
import '../../services/ignore_service.dart';

/// Identifies classes under `lib/` that are **safe candidates** for migration to
/// a Dart 3.12+ *primary constructor* — the syntax that folds field declaration
/// and constructor parameters into the class header, removing the classic
/// Flutter widget boilerplate:
///
/// ```dart
/// // before
/// class PrimaryButton extends StatelessWidget {
///   const PrimaryButton({super.key, required this.label});
///   final String label;
///   ...
/// }
/// ```
///
/// Migrating is *not* always safe (see
/// https://codewithandrea.com/articles/safely-migrate-primary-constructors/): a
/// field doc-comment can silently drop `required`, a constructor body that
/// initializes a field can't be folded, an untyped field breaks, a named
/// `super(...)` call can't be reproduced, and so on. This analyzer therefore
/// reports only the *provably safe* subset — a high-precision "ready to migrate"
/// signal, not a lint of blockers. Anything that fails a check is silently
/// skipped rather than reported.
///
/// Analysis is purely syntactic (no element resolution), consistent with the
/// other AST analyzers in this tool.
class PrimaryConstructorsAnalyzer implements Analyzer {
  const PrimaryConstructorsAnalyzer();

  static const String rule = 'primary_constructor';

  /// Generated-file suffixes skipped in addition to [IgnoreService] patterns.
  /// Mirrors the list guarded by the maintainability analyzer.
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
  String get name => 'primary-constructors';

  @override
  Future<AnalysisResult> analyze(ProjectPaths paths) async {
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

      findings.addAll(_candidatesInFile(source, relPath));
    }

    // Deterministic output: by path, then by line.
    findings.sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      if (byPath != 0) return byPath;
      return (a.line ?? 0).compareTo(b.line ?? 0);
    });

    return AnalysisResult(analyzerName: name, findings: findings);
  }

  /// Parses [source] once and returns a [Finding] for every class in it that is
  /// a safe primary-constructor candidate.
  Iterable<Finding> _candidatesInFile(String source, String relPath) {
    final CompilationUnit unit;
    final LineInfo lineInfo;
    try {
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      unit = parsed.unit;
      lineInfo = parsed.lineInfo;
    } catch (_) {
      return const []; // Unparseable file — skip rather than abort the run.
    }

    final findings = <Finding>[];
    for (final decl in unit.declarations) {
      if (decl is! ClassDeclaration) continue;
      if (!_isSafeCandidate(decl)) continue;

      final nameToken = decl.namePart.typeName;
      findings.add(Finding(
        rule: rule,
        path: relPath,
        severity: Severity.info,
        message: 'Class "${nameToken.lexeme}" is a safe candidate for '
            'primary-constructor migration.',
        line: lineInfo.getLocation(nameToken.offset).lineNumber,
        recommendation: 'Convert to a Dart 3.12+ primary constructor to remove '
            'field/constructor boilerplate.',
      ));
    }
    return findings;
  }

  /// Whether [cls] can be safely rewritten to a primary constructor.
  ///
  /// See the class doc for the rationale behind each rule; every check maps to
  /// one of the blog's "unsafe situations", so a class only qualifies when all
  /// of them pass.
  bool _isSafeCandidate(ClassDeclaration cls) {
    // Exactly one constructor.
    final constructors = [
      for (final m in cls.body.members)
        if (m is ConstructorDeclaration) m,
    ];
    if (constructors.length != 1) return false;
    final ctor = constructors.single;

    // Unnamed + generative.
    if (ctor.name != null) return false;
    if (ctor.factoryKeyword != null) return false;

    // No initializer list (rules out named super calls and `: field = x`).
    if (ctor.initializers.isNotEmpty) return false;

    // Body-less or an empty block body.
    if (!_hasNoBody(ctor.body)) return false;

    // Every parameter must be a field- or super-formal; at least one field
    // formal (otherwise there is no boilerplate to remove).
    final fields = _instanceFieldsByName(cls);
    var hasFieldFormal = false;
    for (final param in ctor.parameters.parameters) {
      if (param is SuperFormalParameter) continue;
      if (param is FieldFormalParameter) {
        hasFieldFormal = true;
        final field = fields[param.name.lexeme];
        // The field must be declared in this class and be migration-safe.
        if (field == null || !_isSafeField(field)) return false;
        continue;
      }
      // A plain parameter can't map to the header — not safe.
      return false;
    }
    return hasFieldFormal;
  }

  /// Maps each instance field variable name to its declaring [FieldDeclaration].
  static Map<String, FieldDeclaration> _instanceFieldsByName(
      ClassDeclaration cls) {
    final map = <String, FieldDeclaration>{};
    for (final m in cls.body.members) {
      if (m is! FieldDeclaration || m.isStatic) continue;
      for (final v in m.fields.variables) {
        map[v.name.lexeme] = m;
      }
    }
    return map;
  }

  /// A field bound by a `this.` formal is safe to fold only when it is `final`,
  /// explicitly typed, uninitialized, non-`late`, un-annotated, and carries no
  /// documentation comment (which could otherwise swallow `required`).
  static bool _isSafeField(FieldDeclaration field) {
    if (!field.fields.isFinal) return false;
    if (field.fields.type == null) return false; // no explicit type annotation
    if (field.fields.isLate) return false;
    if (field.metadata.isNotEmpty) return false;
    if (field.documentationComment != null) return false;
    // Already-initialized fields have nothing to receive from the constructor.
    for (final v in field.fields.variables) {
      if (v.initializer != null) return false;
    }
    return true;
  }

  static bool _hasNoBody(FunctionBody body) {
    if (body is EmptyFunctionBody) return true;
    if (body is BlockFunctionBody) return body.block.statements.isEmpty;
    return false;
  }

  static bool _isGenerated(String relPath) =>
      _generatedSuffixes.any(relPath.endsWith);
}
