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
///    getters, setters, constructors, `build`, and the config's
///    `exempt_methods` boilerplate list, `copyWith` by default),
/// 3. `build()` method length,
/// 4. maximum widget-tree nesting depth,
/// 5. public top-level class count per file (a public class that a sibling
///    public class references, a subtype of a same-file `sealed` class, and a
///    static-only namespace class are supporting types and not counted;
///    `part of` files are skipped entirely — their classes belong to the
///    parent library, and splitting into parts is exactly the decomposition
///    this rule encourages; see [_FileVisitor.computePublicClassCount]),
/// 6. constructor parameter count (excluding `super.key`; private
///    constructors, constructors of private classes, and constructors of
///    immutable non-widget data classes — `const`, or all-final with
///    `copyWith` — are exempt: their parameter count mirrors their field
///    count, not complexity; see [_FileVisitor._isExemptConstructor]), and
/// 7. Dart files directly inside each folder under `lib/`.
///
/// Method and `build()` lengths are measured like file length: distinct
/// *code* lines of the body — blank lines, comments, and the signature don't
/// count.
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

    // Rule 5: public top-level class count (file-level). Skipped for `part of`
    // files: their classes belong to the parent library, and the rule's
    // exemptions (sealed parent, cross-class references) live in sibling files
    // this per-file parse cannot see. Every other rule still applies to parts.
    final isPartFile = unit.directives.whereType<PartOfDirective>().isNotEmpty;
    if (!isPartFile) {
      _addIfOverLimit(
        issues,
        kind: MaintainabilityIssueKind.publicClassCount,
        value: visitor.computePublicClassCount(),
        limit: config.maxPublicClasses,
      );
    }

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
  final List<ClassDeclaration> _publicClasses = [];

  /// Names of `sealed` classes declared in this file (public or private), so
  /// [computePublicClassCount] can exempt their same-file subtypes.
  final Set<String> _sealedClassNames = {};
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

  /// Number of public top-level classes that are *not* a supporting type of
  /// another public class in the same file (Rule 5).
  ///
  /// A public class is exempt from the count when another public class in the
  /// same file references it — by inheritance (`extends`/`implements`/`with`)
  /// or composition (a field/return/parameter type, generic type argument,
  /// factory result, or a construction/throw in a body). This keeps cohesive
  /// pairs together — a contract and its implementation, a carrier and its
  /// element type, a widget and its own public `State` (mutually referenced via
  /// `createState() => FooState()` and `class FooState extends State<Foo>`) —
  /// while still flagging two genuinely unrelated public classes that never
  /// name each other. The reference must come from another *class*: coupling
  /// only through shared top-level functions, enums, or extensions does not
  /// exempt a class. Purely syntactic, consistent with the rest of the walk.
  ///
  /// Two further kinds of class are supporting types by construction:
  /// - a direct subtype of a `sealed` class declared in the same file
  ///   ([_isSealedSubtype]) — the language requires it to stay in this library,
  ///   so "move it to its own file" is not actionable, and
  /// - a static-only namespace class ([_isNamespaceClass]) — a token/constant
  ///   holder that exists to group values, not to model a second concept.
  int computePublicClassCount() {
    final names = <String>{
      for (final c in _publicClasses) c.namePart.typeName.lexeme,
    };
    if (names.length <= 1) return names.length;

    final exempt = <String>{};
    for (final c in _publicClasses) {
      final ownName = c.namePart.typeName.lexeme;
      if (_isSealedSubtype(c) || _isNamespaceClass(c)) exempt.add(ownName);
      c.accept(_ClassReferenceCollector(
        candidates: names,
        ownName: ownName,
        out: exempt,
      ));
    }
    return names.where((n) => !exempt.contains(n)).length;
  }

  /// Whether [node] is a direct subtype (`extends`/`with`/`implements`) of a
  /// `sealed` class declared in this file. Dart requires every subtype of a
  /// sealed class to live in the sealed class's library, so the members of a
  /// sealed union cannot each move to their own file.
  bool _isSealedSubtype(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass;
    if (superclass != null && _sealedClassNames.contains(superclass.name.lexeme)) {
      return true;
    }
    final interfaces = node.implementsClause?.interfaces;
    if (interfaces != null &&
        interfaces.any((t) => _sealedClassNames.contains(t.name.lexeme))) {
      return true;
    }
    final mixins = node.withClause?.mixinTypes;
    return mixins != null &&
        mixins.any((t) => _sealedClassNames.contains(t.name.lexeme));
  }

  /// Whether [node] is a static-only "namespace" class — the
  /// `class Tokens { Tokens._(); static const ... }` idiom: at least one
  /// member, every field/method `static`, and no public way to instantiate it
  /// (every declared constructor is private, or the class is abstract with no
  /// constructor at all). A class with no declared constructor and no
  /// `abstract` modifier has an implicit public constructor and does NOT
  /// qualify.
  bool _isNamespaceClass(ClassDeclaration node) {
    // A public primary constructor (Dart 3.10+) makes the class instantiable.
    final namePart = node.namePart;
    var hasPrivateConstructor = false;
    if (namePart is PrimaryConstructorDeclaration) {
      final ctorName = namePart.constructorName?.name.lexeme;
      if (ctorName == null || !ctorName.startsWith('_')) return false;
      hasPrivateConstructor = true;
    }

    final members = node.body.members;
    if (members.isEmpty && !hasPrivateConstructor) return false;
    for (final member in members) {
      switch (member) {
        case ConstructorDeclaration():
          final name = member.name?.lexeme;
          if (name == null || !name.startsWith('_')) return false;
          hasPrivateConstructor = true;
        case FieldDeclaration():
          if (!member.isStatic) return false;
        case MethodDeclaration():
          if (!member.isStatic) return false;
        default:
          return false; // Unknown member kind — don't exempt.
      }
    }
    return hasPrivateConstructor || node.abstractKeyword != null;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.namePart.typeName.lexeme;
    if (!className.startsWith('_')) _publicClasses.add(node);
    if (node.sealedKeyword != null) _sealedClassNames.add(className);

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
    if (_isExemptConstructor(node)) {
      super.visitConstructorDeclaration(node);
      return;
    }
    // Rule 6: constructor parameter count. `super.key` is mandatory Flutter
    // widget boilerplate, not real API surface, so it doesn't count.
    final count = node.parameters.parameters
        .where((param) =>
            !(param is SuperFormalParameter && param.name.lexeme == 'key'))
        .length;
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
        value: _codeLineSpan(node.body),
        limit: _config.buildMethodLines,
        line: _lineOf(node.offset),
      );
      // Rule 4: nesting depth of this build() body.
      final depth = _nesting.maxDepth(node.body);
      if (depth > maxNestingDepth) {
        maxNestingDepth = depth;
        maxNestingLine = _lineOf(node.offset);
      }
    } else if (!_config.exemptMethods.contains(node.name.lexeme)) {
      // Rule 2: method length.
      MaintainabilityAnalyzer._addIfOverLimit(
        issues,
        kind: MaintainabilityIssueKind.methodLength,
        value: _codeLineSpan(node.body),
        limit: _config.methodLines,
        subject: node.name.lexeme,
        line: _lineOf(node.offset),
      );
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (!node.isGetter &&
        !node.isSetter &&
        !_config.exemptMethods.contains(node.name.lexeme)) {
      // Rule 2: top-level / local function length.
      MaintainabilityAnalyzer._addIfOverLimit(
        issues,
        kind: MaintainabilityIssueKind.methodLength,
        value: _codeLineSpan(node.functionExpression.body),
        limit: _config.methodLines,
        subject: node.name.lexeme,
        line: _lineOf(node.offset),
      );
    }
    super.visitFunctionDeclaration(node);
  }

  /// Whether Rule 6 skips [node]. Exempt are:
  /// - private constructors (`Foo._(...)`) and constructors of private
  ///   classes — not public API surface; call sites are library-local (e.g. a
  ///   private FFI-binding holder taking one resolved symbol per parameter),
  /// - non-factory constructors of immutable non-widget data classes
  ///   ([_isImmutableDataClass]) that are `const` or whose class declares
  ///   `copyWith` (the canonical Dart data-class marker; a non-const ctor
  ///   alone — e.g. a service taking many injected dependencies — is not
  ///   enough) — like the `copyWith` method-length exemption, a data
  ///   carrier's parameter count mirrors its field count, not complexity.
  /// Widgets stay flagged: a widget constructor with many parameters is a
  /// composition smell the rule exists to catch.
  bool _isExemptConstructor(ConstructorDeclaration node) {
    if (node.name?.lexeme.startsWith('_') ?? false) return true;
    final cls = node.thisOrAncestorOfType<ClassDeclaration>();
    if (cls == null) return false;
    if (cls.namePart.typeName.lexeme.startsWith('_')) return true;
    return node.factoryKeyword == null &&
        (node.constKeyword != null || _declaresCopyWith(cls)) &&
        _isImmutableDataClass(cls);
  }

  /// Whether [cls] declares a `copyWith` method.
  bool _declaresCopyWith(ClassDeclaration cls) => cls.body.members.any(
      (m) => m is MethodDeclaration && m.name.lexeme == 'copyWith');

  /// An immutable data class for [_isExemptConstructor]: every instance field
  /// `final`, not a subclass of a known widget base, and no
  /// `build(BuildContext)` method (guards against widget bases the
  /// [MaintainabilityAnalyzer._widgetSuperclasses] set doesn't know —
  /// StatelessWidget subclasses are also const + all-final, so the widget
  /// checks are load-bearing).
  bool _isImmutableDataClass(ClassDeclaration cls) {
    final superName = cls.extendsClause?.superclass.name.lexeme;
    if (superName != null &&
        MaintainabilityAnalyzer._widgetSuperclasses.contains(superName)) {
      return false;
    }
    for (final member in cls.body.members) {
      if (member is FieldDeclaration &&
          !member.isStatic &&
          !member.fields.isFinal) {
        return false;
      }
      if (member is MethodDeclaration && _isBuildMethod(member)) return false;
    }
    return true;
  }

  /// A widget `build` method: named `build` with a first `BuildContext`
  /// parameter and at most one more (Riverpod's
  /// `build(BuildContext context, WidgetRef ref)`). The parameter type is
  /// checked via source text to stay independent of analyzer AST class churn
  /// (no element resolution).
  bool _isBuildMethod(MethodDeclaration node) {
    if (node.name.lexeme != 'build') return false;
    final params = node.parameters?.parameters;
    if (params == null || params.isEmpty || params.length > 2) return false;
    return params.first.toSource().contains('BuildContext');
  }

  /// Distinct code lines within [node]'s token range — the same counting rule
  /// as [MaintainabilityAnalyzer._codeLineCount], bounded to one node: blank
  /// lines carry no token and comments hang off tokens as `precedingComments`,
  /// so neither is counted, and the signature outside a body contributes
  /// nothing when [node] is a [FunctionBody].
  int _codeLineSpan(AstNode node) {
    final lines = <int>{};
    final last = node.endToken;
    Token? token = node.beginToken;
    while (token != null) {
      final start = _lineOf(token.offset);
      final end = _lineOf(token.end);
      for (var l = start; l <= end; l++) {
        lines.add(l);
      }
      if (token == last) break;
      final next = token.next;
      if (next == null || next == token) break;
      token = next;
    }
    return lines.length;
  }

  int _lineOf(int offset) => _lineInfo.getLocation(offset).lineNumber;
}

/// Records which of [candidates] a single class declaration references, so
/// [_FileVisitor.computePublicClassCount] can tell whether one public class is
/// a supporting type of another. Both type positions ([NamedType] — supertypes,
/// field/return/parameter types, generic arguments) and identifier positions
/// ([SimpleIdentifier] — unresolved constructions like `FooState()` or
/// `throw SomeException(...)`, which parse as invocations without resolution)
/// are collected. The class's own name is ignored so self-references don't
/// exempt a class from the count.
class _ClassReferenceCollector extends RecursiveAstVisitor<void> {
  _ClassReferenceCollector({
    required this.candidates,
    required this.ownName,
    required this.out,
  });

  final Set<String> candidates;
  final String ownName;
  final Set<String> out;

  void _record(String name) {
    if (name != ownName && candidates.contains(name)) out.add(name);
  }

  @override
  void visitNamedType(NamedType node) {
    _record(node.name.lexeme);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _record(node.name);
    super.visitSimpleIdentifier(node);
  }
}
