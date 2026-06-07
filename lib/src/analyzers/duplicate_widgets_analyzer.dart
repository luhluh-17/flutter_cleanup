import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import '../analysis/analyzer.dart';
import '../analysis/path_utils.dart';
import '../models/finding.dart';
import '../models/project_paths.dart';
import '../services/ignore_service.dart';

/// Detects structurally highly similar Flutter widgets under `lib/` by comparing
/// the widget-tree shape of each widget's `build()` method.
///
/// This complements [DuplicateCodeAnalyzer]: that one compares whole *files* as
/// normalized token streams, while this one compares the *widget structure*
/// recovered from the Dart AST, ignoring strings, numbers, identifiers, and
/// callback bodies. Two widgets that build the same tree shape score highly even
/// when their text differs substantially.
///
/// Each widget's `build()` body is reduced to a structural "fingerprint" — the
/// pre-order sequence of widget constructor names (`Card`, `Column`, `Text`, …).
/// Fingerprints are compared with Jaccard similarity over size-2 shingles, and
/// pairs at or above [similarityThreshold] are reported.
///
/// ## Limitations (syntactic AST, no resolution)
/// - Helper methods are not analyzed: only the `build()` body is walked, so
///   widgets extracted into helpers (`Widget _buildHeader() => …`) are invisible.
/// - Widget trees are extracted only from `build()`, not from other methods or
///   top-level widget-returning functions.
/// - No element resolution: a PascalCase identifier in call position is *assumed*
///   to be a widget/value constructor. A small blocklist drops common
///   non-structural value types (`EdgeInsets`, `Color`, …).
/// - StatefulWidget `build` lives in the companion `State` class; the widget name
///   is recovered from `extends State<Foo>` (fallback: the State class name).
/// - No framework awareness (Riverpod / GoRouter / code generation).
/// - O(n²) pair comparison; fine for typical projects, not tuned for huge
///   monorepos. Ordered shingles capture local structure, not full tree-edit
///   distance.
class DuplicateWidgetsAnalyzer implements Analyzer {
  const DuplicateWidgetsAnalyzer();

  static const String rule = 'duplicate_widget';

  /// Minimum Jaccard similarity (0.0–1.0) for a pair to be reported. High by
  /// design: this is a high-precision signal, so we'd rather miss a borderline
  /// pair than flood the report with weak matches.
  static const double similarityThreshold = 0.85;

  /// Widgets whose fingerprint has fewer than this many nodes are excluded.
  /// Tiny widgets (`Text(...)`, `Container(child: Text(...))`) are the biggest
  /// noise source — almost any two of them look alike — so they don't compete.
  static const int minWidgetNodes = 8;

  /// Consecutive fingerprint entries per shingle (parent/child + sibling
  /// adjacency). Mirrors the shingle idea in [DuplicateCodeAnalyzer], but over
  /// widget names instead of source tokens.
  static const int _shingleSize = 2;

  /// PascalCase constructors that are *not* widgets — Flutter value/config types
  /// that show up inside `build()` and would otherwise inflate similarity with
  /// structural noise. Kept intentionally small; documented as a known
  /// trade-off.
  static const Set<String> _nonWidgetBlocklist = {
    'EdgeInsets',
    'Duration',
    'Color',
    'Colors',
    'Offset',
    'Size',
    'TextStyle',
    'Border',
    'BorderRadius',
    'Radius',
    'Key',
    'ValueKey',
    'GlobalKey',
  };

  /// `Type.method(...)` calls whose method is a well-known *lookup* rather than a
  /// named constructor — these return ambient values, not freshly built widgets,
  /// so the leading `Type` should not be counted (e.g. `Theme.of`,
  /// `Provider.of`).
  static const Set<String> _nonConstructorMethods = {'of', 'maybeOf'};

  @override
  String get name => 'duplicate-widgets';

  @override
  Future<AnalysisResult> analyze(ProjectPaths paths) async {
    final libDir = Directory(paths.libDir);
    if (!libDir.existsSync()) return AnalysisResult.empty(name);

    final ignore = IgnoreService.forProject(paths.root);

    // 1. Collect widgets from every Dart file under lib/. Staying inside libDir
    //    excludes test/, build/, and .dart_tool/ by construction. Ignored files
    //    (defaults + .flutter_cleanup.yaml) never contribute widgets.
    final widgets = <_WidgetInfo>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.dart') continue;
      final relPath = toPosixRelative(paths.root, entity.path);
      if (ignore.isIgnored(relPath)) continue;

      final String source;
      try {
        source = entity.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      widgets.addAll(_widgetsInFile(source, relPath));
    }

    // 2. Keep only widgets large enough to carry signal, then sort for
    //    deterministic output (path first, then name).
    final comparable = [
      for (final w in widgets)
        if (w.fingerprint.length >= minWidgetNodes) w,
    ]..sort((a, b) {
        final byPath = a.filePath.compareTo(b.filePath);
        return byPath != 0 ? byPath : a.name.compareTo(b.name);
      });

    // 3. Compare every unordered pair; emit one finding per similar pair.
    final findings = <Finding>[];
    for (var i = 0; i < comparable.length; i++) {
      for (var j = i + 1; j < comparable.length; j++) {
        final a = comparable[i];
        final b = comparable[j];
        final score = _jaccard(a.shingles, b.shingles);
        if (score >= similarityThreshold) {
          final percent = (score * 100).round();
          findings.add(Finding(
            rule: rule,
            path: a.filePath,
            severity: Severity.info,
            message: 'Widget "${a.name}" is highly similar to "${b.name}" '
                'in ${b.filePath} '
                '($percent% similarity, ${a.fingerprint.length} nodes).',
          ));
        }
      }
    }

    return AnalysisResult(analyzerName: name, findings: findings);
  }

  /// Parses [source] and returns every Stateless/Stateful widget that has a
  /// reachable `build()` method, fingerprinted.
  Iterable<_WidgetInfo> _widgetsInFile(String source, String relPath) {
    final List<ClassDeclaration> classes;
    try {
      final unit = parseString(content: source, throwIfDiagnostics: false).unit;
      classes = [
        for (final d in unit.declarations)
          if (d is ClassDeclaration) d,
      ];
    } catch (_) {
      // Unparseable file (very malformed) — skip rather than abort the run.
      return const [];
    }

    final result = <_WidgetInfo>[];
    for (final cls in classes) {
      final superName = cls.extendsClause?.superclass.name.lexeme;
      if (superName != 'StatelessWidget' && superName != 'State') continue;

      final build = _buildMethod(cls);
      if (build == null) continue; // widgets without a build method are ignored

      final widgetName = superName == 'State'
          ? _stateWidgetName(cls)
          : cls.namePart.typeName.lexeme;

      final collector = _FingerprintCollector();
      build.body.accept(collector);
      result.add(_WidgetInfo(widgetName, relPath, collector.names));
    }
    return result;
  }

  /// Returns the `build` method of [cls], or null if it has none.
  MethodDeclaration? _buildMethod(ClassDeclaration cls) {
    for (final member in cls.body.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        return member;
      }
    }
    return null;
  }

  /// Recovers the widget name for a `State` subclass: the `Foo` in
  /// `extends State<Foo>`, falling back to the State class name with a trailing
  /// `State` stripped (e.g. `_LoginPageState` -> `_LoginPage`).
  String _stateWidgetName(ClassDeclaration cls) {
    final args = cls.extendsClause?.superclass.typeArguments?.arguments;
    if (args != null && args.isNotEmpty) {
      final first = args.first;
      if (first is NamedType) return first.name.lexeme;
    }
    var name = cls.namePart.typeName.lexeme;
    if (name.endsWith('State')) {
      name = name.substring(0, name.length - 'State'.length);
    }
    return name.replaceAll(RegExp(r'^_+'), '');
  }

  /// Jaccard similarity between two sets: |A∩B| / |A∪B|. Same formula as the
  /// token-based [DuplicateCodeAnalyzer], applied to widget shingles.
  double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final intersection = a.intersection(b).length;
    final union = a.length + b.length - intersection;
    return union == 0 ? 0.0 : intersection / union;
  }
}

/// Builds the set of shingles for [fingerprint]. Falls back to the bare name set
/// when the fingerprint is shorter than the shingle size.
Set<String> _shingleSet(List<String> fingerprint) {
  const shingleSize = DuplicateWidgetsAnalyzer._shingleSize;
  if (fingerprint.length < shingleSize) return fingerprint.toSet();
  final set = <String>{};
  for (var i = 0; i + shingleSize <= fingerprint.length; i++) {
    set.add(fingerprint.sublist(i, i + shingleSize).join(' '));
  }
  return set;
}

/// A discovered widget and its structural fingerprint.
class _WidgetInfo {
  _WidgetInfo(this.name, this.filePath, this.fingerprint)
      : shingles = _shingleSet(fingerprint);

  /// Widget class name (the StatelessWidget, or `Foo` for `State<Foo>`).
  final String name;

  /// Project-relative POSIX path of the defining file.
  final String filePath;

  /// Pre-order sequence of widget constructor names from `build()`.
  final List<String> fingerprint;

  /// Cached shingle set used for Jaccard comparison.
  final Set<String> shingles;
}

/// Walks a `build()` body in pre-order, recording widget constructor names.
///
/// `RecursiveAstVisitor` visits a node before recursing into its children, so
/// constructor calls are recorded parent-first — exactly the structural order
/// (`Card`, `Column`, `Text`, `Text`) the fingerprint represents.
class _FingerprintCollector extends RecursiveAstVisitor<void> {
  final List<String> names = [];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `const Foo(...)` / `new Foo(...)`. For a named constructor like
    // `const EdgeInsets.all(8)` the unresolved parser models the type as a
    // *prefixed* name (prefix `EdgeInsets`, name `all`), so prefer the prefix —
    // it is the real class. Falls back to the bare type name (`Foo`).
    final type = node.constructorName.type;
    _record(type.importPrefix?.name.lexeme ?? type.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Without resolution, an unprefixed constructor call `Foo(...)` parses as a
    // MethodInvocation, not an InstanceCreationExpression — so widgets show up
    // here, identified heuristically by a PascalCase name.
    final target = node.target;
    final method = node.methodName.name;
    if (target == null) {
      if (_isPascalCase(method)) _record(method);
    } else if (target is SimpleIdentifier &&
        _isPascalCase(target.name) &&
        !_isPascalCase(method) &&
        !DuplicateWidgetsAnalyzer._nonConstructorMethods.contains(method)) {
      // `Type.named(...)` — a named constructor like `ListView.builder` or
      // `Text.rich`. Record the type, not the constructor name.
      _record(target.name);
    }
    super.visitMethodInvocation(node);
  }

  void _record(String name) {
    if (!DuplicateWidgetsAnalyzer._nonWidgetBlocklist.contains(name)) {
      names.add(name);
    }
  }
}

bool _isPascalCase(String name) =>
    name.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(name);
