// EXPERIMENTAL RESEARCH SPIKE — not production code, not wired into the CLI.
//
// Question being evaluated: does comparing the real Dart *widget-tree*
// structure (via the analyzer AST) surface more useful duplicate candidates
// than the existing token-based `DuplicateCodeAnalyzer` (which compares whole
// *files* as normalized token streams)?
//
// This tool scans `<project>/lib/**/*.dart`, finds Stateless/Stateful widgets,
// reduces each widget's `build()` method to a structural "fingerprint" (the
// pre-order sequence of widget constructor names, ignoring identifiers, string
// and numeric literals, and callback bodies), and reports the top 20 most
// structurally similar widget pairs by Jaccard similarity over fingerprint
// shingles.
//
// Run:
//   dart run tool/widget_similarity_spike.dart <flutter_project_path>
//
// Deliberately isolated under tool/ so it can be discarded if the experiment
// fails — deleting this one file (and reverting the `analyzer` dev-dependency)
// removes the spike entirely. It reuses two helpers from the package
// (`toPosixRelative`, `IgnoreService`) but modifies nothing in lib/.
//
// Known limitations (see also the writeup):
//   * Syntactic parse only (no element resolution): a PascalCase identifier in
//     call position is *assumed* to be a widget/value constructor. A small
//     blocklist drops common non-structural value types (EdgeInsets, Color, …).
//   * Only the `build` method body is walked — widgets extracted into helper
//     methods (`_buildHeader()`) are not inlined and so are invisible here.
//   * StatefulWidget `build` lives in the companion `State` class; the widget
//     name is recovered from `extends State<Foo>` (fallback: State class name).
//   * O(n^2) pair comparison; fine for typical projects, not tuned for huge
//     monorepos. Ordered shingles capture local structure, not full tree-edit
//     distance.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_cleanup/src/analysis/path_utils.dart';
import 'package:flutter_cleanup/src/services/ignore_service.dart';
import 'package:path/path.dart' as p;

/// Number of most-similar pairs to print.
const int _topN = 20;

/// Consecutive fingerprint entries per shingle (parent/child + sibling
/// adjacency). Mirrors the shingle idea in `DuplicateCodeAnalyzer`, but over
/// widget names instead of source tokens.
const int _shingleSize = 2;

/// PascalCase constructors that are *not* widgets — Flutter value/config types
/// that show up inside `build()` and would otherwise inflate similarity with
/// structural noise. Kept intentionally small; documented as a known trade-off.
const Set<String> _nonWidgetBlocklist = {
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
/// so the leading `Type` should not be counted (e.g. `Theme.of`, `Provider.of`).
const Set<String> _nonConstructorMethods = {'of', 'maybeOf'};

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

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/widget_similarity_spike.dart <flutter_project_path>');
    exit(64); // EX_USAGE
  }

  final root = p.normalize(p.absolute(args.first));
  final libDir = Directory(p.join(root, 'lib'));
  if (!libDir.existsSync()) {
    stderr.writeln('error: no lib/ directory found under $root');
    exit(1);
  }

  final stopwatch = Stopwatch()..start();
  final ignore = IgnoreService.forProject(root);

  // Collect Dart files under lib/ only — staying inside lib/ excludes test/,
  // build/, and .dart_tool/ by construction. Generated/ignored files are
  // dropped via the project's IgnoreService (honors .flutter_cleanup.yaml).
  final widgets = <_WidgetInfo>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || p.extension(entity.path) != '.dart') continue;
    final relPath = toPosixRelative(root, entity.path);
    if (ignore.isIgnored(relPath)) continue;

    final String source;
    try {
      source = entity.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    widgets.addAll(_widgetsInFile(source, relPath));
  }

  // Only widgets with a non-empty fingerprint are comparable.
  final comparable = [for (final w in widgets) if (w.fingerprint.isNotEmpty) w];

  // Compare every unordered pair; keep them all, then sort by score.
  final pairs = <_Pair>[];
  for (var i = 0; i < comparable.length; i++) {
    for (var j = i + 1; j < comparable.length; j++) {
      final score = _jaccard(comparable[i].shingles, comparable[j].shingles);
      pairs.add(_Pair(comparable[i], comparable[j], score));
    }
  }
  pairs.sort((a, b) => b.score.compareTo(a.score));

  stopwatch.stop();

  _report(pairs);
  stdout.writeln('');
  stdout.writeln('Widgets analyzed: ${comparable.length}');
  stdout.writeln('Pairs compared: ${pairs.length}');
  stdout.writeln('Time elapsed: ${stopwatch.elapsedMilliseconds} ms');
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
        !_nonConstructorMethods.contains(method)) {
      // `Type.named(...)` — a named constructor like `ListView.builder` or
      // `Text.rich`. Record the type, not the constructor name.
      _record(target.name);
    }
    super.visitMethodInvocation(node);
  }

  void _record(String name) {
    if (!_nonWidgetBlocklist.contains(name)) names.add(name);
  }
}

bool _isPascalCase(String name) =>
    name.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(name);

/// Builds the set of [_shingleSize]-entry shingles for [fingerprint]. Falls back
/// to the bare name set when the fingerprint is shorter than the shingle size.
Set<String> _shingleSet(List<String> fingerprint) {
  if (fingerprint.length < _shingleSize) return fingerprint.toSet();
  final set = <String>{};
  for (var i = 0; i + _shingleSize <= fingerprint.length; i++) {
    set.add(fingerprint.sublist(i, i + _shingleSize).join(' '));
  }
  return set;
}

/// Jaccard similarity between two sets: |A∩B| / |A∪B|. Same formula as the
/// existing token-based `DuplicateCodeAnalyzer`, applied to widget shingles.
double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final intersection = a.intersection(b).length;
  final union = a.length + b.length - intersection;
  return union == 0 ? 0.0 : intersection / union;
}

/// A scored, unordered widget pair.
class _Pair {
  _Pair(this.a, this.b, this.score);
  final _WidgetInfo a;
  final _WidgetInfo b;
  final double score;
}

/// Prints the top [_topN] pairs by similarity, with both fingerprints.
void _report(List<_Pair> pairs) {
  if (pairs.isEmpty) {
    stdout.writeln('No comparable widget pairs found.');
    return;
  }
  final limit = pairs.length < _topN ? pairs.length : _topN;
  for (var i = 0; i < limit; i++) {
    final pair = pairs[i];
    stdout.writeln('Similarity: ${pair.score.toStringAsFixed(2)}');
    stdout.writeln('');
    stdout.writeln(pair.a.name);
    stdout.writeln(pair.a.filePath);
    stdout.writeln('');
    stdout.writeln(pair.b.name);
    stdout.writeln(pair.b.filePath);
    stdout.writeln('');
    stdout.writeln('Fingerprint (${pair.a.name})');
    stdout.writeln(pair.a.fingerprint.join('\n'));
    stdout.writeln('');
    stdout.writeln('Fingerprint (${pair.b.name})');
    stdout.writeln(pair.b.fingerprint.join('\n'));
    stdout.writeln('');
    stdout.writeln('-' * 40);
    stdout.writeln('');
  }
}
