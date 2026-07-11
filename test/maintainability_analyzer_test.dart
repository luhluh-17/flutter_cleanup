import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('maintainability_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- Fixture helpers -------------------------------------------------------

  void writePubspec({String name = 'sample'}) {
    File(p.join(tempDir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: $name\n');
  }

  /// Writes a Dart file at [relUnderLib] (relative to `lib/`).
  void writeDart(String relUnderLib, String contents) {
    final file =
        File(p.join(tempDir.path, 'lib', p.joinAll(relUnderLib.split('/'))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void writeConfig(String contents) {
    File(p.join(tempDir.path, '.flutter_cleanup.yaml'))
        .writeAsStringSync(contents);
  }

  Future<AnalysisResult> run() =>
      const MaintainabilityAnalyzer().analyze(ProjectPaths(tempDir.path));

  Iterable<Finding> findingsOf(AnalysisResult r, String messageSubstring) =>
      r.findings.where((f) => f.message.contains(messageSubstring));

  /// A file with exactly [lines] lines of code and no class (classified as a
  /// generic file, so the `file_lines` limit of 300 applies).
  String fileWithLines(int lines) {
    final buffer = StringBuffer();
    for (var i = 0; i < lines; i++) {
      buffer.writeln('final v$i = $i;');
    }
    return buffer.toString();
  }

  /// A `StatelessWidget` file (classified as a widget file, limit 250) padded to
  /// `6 + padLines` code lines.
  String widgetFile(String name, {int padLines = 0}) {
    final b = StringBuffer("import 'package:flutter/material.dart';\n");
    b.writeln('class $name extends StatelessWidget {');
    b.writeln('  const $name({super.key});');
    b.writeln('  @override');
    b.writeln('  Widget build(BuildContext context) => const Placeholder();');
    b.writeln('}');
    for (var i = 0; i < padLines; i++) {
      b.writeln('final v$i = $i;');
    }
    return b.toString();
  }

  /// A plain class file padded to `3 + padLines` code lines. [base] optionally
  /// sets an `extends` clause (used to make it a controller).
  String plainClassFile(String className, {String? base, int padLines = 0}) {
    final ext = base == null ? '' : ' extends $base';
    final b = StringBuffer();
    b.writeln('class $className$ext {');
    b.writeln('  $className();');
    b.writeln('}');
    for (var i = 0; i < padLines; i++) {
      b.writeln('final v$i = $i;');
    }
    return b.toString();
  }

  /// A function named [name] whose body spans roughly [bodyStatements] lines.
  String functionWithLines(String name, int bodyStatements) {
    final buffer = StringBuffer('int $name() {\n');
    for (var i = 0; i < bodyStatements; i++) {
      buffer.writeln('  var v$i = $i;');
    }
    buffer.writeln('  return 0;');
    buffer.writeln('}');
    return buffer.toString();
  }

  // --- File length: generic --------------------------------------------------

  group('generic file length (limit 300)', () {
    test('a file over the limit is reported', () async {
      writePubspec();
      writeDart('big.dart', fileWithLines(310));

      final findings = findingsOf(await run(), 'File contains').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'file_length');
      expect(findings.single.severity, Severity.warning);
      expect(findings.single.message, contains('310 lines'));
      expect(findings.single.message, contains('limit: 300'));
      expect(findings.single.recommendation, isNotNull);
    });

    test('exactly at the limit is allowed (≤ is inclusive)', () async {
      writePubspec();
      writeDart('edge.dart', fileWithLines(300));
      expect(findingsOf(await run(), 'File contains'), isEmpty);
    });

    test('one over the limit is flagged', () async {
      writePubspec();
      writeDart('edge.dart', fileWithLines(301));
      expect(findingsOf(await run(), 'File contains'), hasLength(1));
    });

    test('blank and comment-only lines are not counted', () async {
      writePubspec();
      final buffer = StringBuffer();
      for (var i = 0; i < 200; i++) {
        buffer.writeln('final v$i = $i;');
        buffer.writeln();
        buffer.writeln('// comment $i');
      }
      writeDart('padded.dart', buffer.toString());
      expect(findingsOf(await run(), 'File contains'), isEmpty);
    });
  });

  // --- File length: widget vs controller classification ----------------------

  group('file classification', () {
    test('a widget file is measured against the 250-line limit', () async {
      writePubspec();
      // 6 + 250 = 256 code lines: over the widget limit (250), under the
      // generic/controller limit (300).
      writeDart('big_widget.dart', widgetFile('BigWidget', padLines: 250));

      final findings = findingsOf(await run(), 'Widget file contains').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'widget_file_length');
      expect(findings.single.message, contains('limit: 250'));
    });

    test('a widget file under 250 lines is not reported', () async {
      writePubspec();
      writeDart('ok_widget.dart', widgetFile('OkWidget', padLines: 100));
      expect(findingsOf(await run(), 'Widget file contains'), isEmpty);
    });

    test('a *_controller.dart file uses the 300-line limit', () async {
      writePubspec();
      // 3 + 270 = 273 lines: over the widget limit (250) but under 300, so a
      // controller must NOT be flagged (proves it is not treated as a widget).
      writeDart('home_controller.dart',
          plainClassFile('Home', padLines: 270));
      expect((await run()).findings, isEmpty);
    });

    test('a *_controller.dart file over 300 lines is reported as a controller',
        () async {
      writePubspec();
      writeDart('home_controller.dart',
          plainClassFile('Home', padLines: 310));

      final findings = findingsOf(await run(), 'Controller contains').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'controller_length');
      expect(findings.single.message, contains('limit: 300'));
    });

    test('a class extending a notifier is classified as a controller',
        () async {
      writePubspec();
      writeDart('counter.dart',
          plainClassFile('Counter', base: 'ChangeNotifier', padLines: 310));

      expect(findingsOf(await run(), 'Controller contains'), hasLength(1));
    });

    test('a class named *Controller is classified as a controller', () async {
      writePubspec();
      writeDart('logic.dart',
          plainClassFile('AuthController', padLines: 310));

      expect(findingsOf(await run(), 'Controller contains'), hasLength(1));
    });
  });

  // --- Method length (limit 30) ----------------------------------------------

  group('method length (limit 30)', () {
    test('a long method is reported', () async {
      writePubspec();
      writeDart('svc.dart', functionWithLines('generateMonthlyReport', 40));

      final findings =
          findingsOf(await run(), 'generateMonthlyReport()').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'method_length');
      expect(findings.single.message, contains('limit: 30'));
    });

    test('blank lines, comments and the signature are not counted', () async {
      writePubspec();
      // 28 code lines in the body, padded with blanks, comments and a
      // multi-line signature: raw span is way over 30, code lines are not.
      final b = StringBuffer();
      b.writeln('int spread(');
      b.writeln('  int first,');
      b.writeln('  int second,');
      b.writeln(') {');
      for (var i = 0; i < 27; i++) {
        b.writeln('  var v$i = $i;');
        b.writeln();
        b.writeln('  // step $i');
      }
      b.writeln('  return 0;');
      b.writeln('}');
      writeDart('spread.dart', b.toString());
      expect(findingsOf(await run(), 'Method spread()'), isEmpty);
    });

    test('copyWith is exempt by default', () async {
      writePubspec();
      final args =
          List.generate(40, (i) => '        p$i: p$i ?? this.p$i,').join('\n');
      writeDart('state.dart', '''
class State {
  const State();
  State copyWith() {
    return State(
$args
    );
  }
}
''');
      expect(findingsOf(await run(), 'Method copyWith()'), isEmpty);
    });

    test('an empty exempt_methods list re-enables copyWith', () async {
      writePubspec();
      writeConfig('maintainability:\n  exempt_methods: []\n');
      final args =
          List.generate(40, (i) => '        p$i: p$i ?? this.p$i,').join('\n');
      writeDart('state.dart', '''
class State {
  const State();
  State copyWith() {
    return State(
$args
    );
  }
}
''');
      expect(findingsOf(await run(), 'Method copyWith()'), hasLength(1));
    });

    test('getters, setters and constructors are ignored', () async {
      writePubspec();
      final body = List.generate(40, (i) => '    var v$i = $i;').join('\n');
      writeDart('model.dart', '''
class Model {
  Model() {
$body
  }

  int get value {
$body
    return 0;
  }

  set value(int v) {
$body
  }
}
''');
      expect(findingsOf(await run(), 'Method'), isEmpty);
    });
  });

  // --- build() length (limit 60) ---------------------------------------------

  group('build() length (limit 60)', () {
    test('a long build() is reported as a build finding', () async {
      writePubspec();
      final body = List.generate(70, (i) => '    final w$i = $i;').join('\n');
      writeDart('page.dart', '''
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
$body
    return const Placeholder();
  }
}
''');

      final result = await run();
      final build = findingsOf(result, 'build() method').toList();
      expect(build, hasLength(1));
      expect(build.single.rule, 'build_method_length');
      expect(build.single.message, contains('limit: 60'));
      // Not also reported as a generic "Method build()".
      expect(findingsOf(result, 'Method build()'), isEmpty);
    });

    test('a ConsumerWidget build(context, ref) is a build method, not a plain '
        'method', () async {
      writePubspec();
      // 40 code lines: over the 30-line method limit but under the 60-line
      // build limit — it must not be flagged at all.
      final body = List.generate(38, (i) => '    final w$i = $i;').join('\n');
      writeDart('panel.dart', '''
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Panel extends ConsumerWidget {
  const Panel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
$body
    return const Placeholder();
  }
}
''');
      final result = await run();
      expect(findingsOf(result, 'Method build()'), isEmpty);
      expect(findingsOf(result, 'build() method'), isEmpty);
    });

    test('blank and comment lines inside build() are not counted', () async {
      writePubspec();
      // 55 statements + return: ≤ 60 code lines even though blanks/comments
      // push the raw span far over the limit.
      final body = List.generate(55, (i) => '    final w$i = $i;\n\n    // w$i')
          .join('\n');
      writeDart('page.dart', '''
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
$body
    return const Placeholder();
  }
}
''');
      expect(findingsOf(await run(), 'build() method'), isEmpty);
    });
  });

  // --- Nesting depth (limit 5) -----------------------------------------------

  group('nesting depth (limit 5)', () {
    test('a deeply nested widget tree is reported', () async {
      writePubspec();
      writeDart('deep.dart', '''
import 'package:flutter/material.dart';

class Deep extends StatelessWidget {
  const Deep({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: Center(
                  child: Text('hi'),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
''');

      final findings = findingsOf(await run(), 'nesting depth').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'widget_nesting_depth');
      expect(findings.single.message,
          contains('Maximum widget nesting depth is 8'));
      expect(findings.single.message, contains('limit: 5'));
    });

    test('a shallow tree is not reported', () async {
      writePubspec();
      writeDart('shallow.dart', '''
import 'package:flutter/material.dart';

class Shallow extends StatelessWidget {
  const Shallow({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('hi'));
  }
}
''');
      expect(findingsOf(await run(), 'nesting depth'), isEmpty);
    });
  });

  // --- Public class count (limit 1) ------------------------------------------

  group('public class count (limit 1)', () {
    test('more than one public class is reported', () async {
      writePubspec();
      writeDart('two.dart', 'class Foo {}\nclass Bar {}\n');

      final findings =
          findingsOf(await run(), 'public classes').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'public_class_count');
      expect(findings.single.message, contains('2 public classes'));
      expect(findings.single.message, contains('limit: 1'));
    });

    test('one public class plus private classes is allowed', () async {
      writePubspec();
      writeDart('one.dart', 'class Foo {}\nclass _Bar {}\nclass _Baz {}\n');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('a StatefulWidget with its private State passes', () async {
      writePubspec();
      writeDart('sw.dart', '''
import 'package:flutter/material.dart';

class Foo extends StatefulWidget {
  const Foo({super.key});
  @override
  State<Foo> createState() => _FooState();
}

class _FooState extends State<Foo> {
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('a contract plus its implementation passes (inheritance)', () async {
      writePubspec();
      writeDart('platform_info.dart', '''
abstract class PlatformInfo {
  bool get isWindows;
}

class DartPlatformInfo implements PlatformInfo {
  @override
  bool get isWindows => true;
}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('a carrier plus its element type passes (composition)', () async {
      writePubspec();
      writeDart('inspection.dart', '''
class ExpressionChild {
  const ExpressionChild(this.name);
  final String name;
}

class ExpressionInspection {
  const ExpressionInspection(this.children);
  final List<ExpressionChild> children;
}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('two mutually-referencing classes pass (composition)', () async {
      writePubspec();
      writeDart('cancellation.dart', '''
class CancellationToken {
  CancellationToken(this.source);
  final CancellationTokenSource source;
}

class CancellationTokenSource {
  CancellationToken get token => CancellationToken(this);
}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('a widget with a public State class passes', () async {
      writePubspec();
      writeDart('path_field.dart', '''
import 'package:flutter/material.dart';

class PathField extends StatefulWidget {
  const PathField({super.key});
  @override
  State<PathField> createState() => PathFieldState();
}

class PathFieldState extends State<PathField> {
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('a sealed hierarchy in one file passes', () async {
      writePubspec();
      // The language requires every subtype of a sealed class to stay in the
      // same library, so none of these can move to its own file.
      writeDart('event.dart', '''
sealed class Event {}

final class StartedEvent extends Event {}

final class StoppedEvent extends Event {}

class FailedEvent implements Event {}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('an abstract (non-sealed) hierarchy is still reported', () async {
      writePubspec();
      // Unlike sealed subtypes, these subclasses CAN move to their own files.
      writeDart('failure.dart', '''
abstract class Failure {}

class DomainFailure extends Failure {}

class InfrastructureFailure extends Failure {}
''');
      final findings = findingsOf(await run(), 'public classes').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('2 public classes'));
    });

    test('a static-only namespace class does not count', () async {
      writePubspec();
      writeDart('theme.dart', '''
class AppColors {
  AppColors._();
  static const int primary = 0xFF000000;
}

class AppSpacing {
  AppSpacing._();
  static const double small = 4;
}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('static members with an implicit public constructor still count',
        () async {
      writePubspec();
      // No declared constructor and not abstract → publicly instantiable, so
      // the namespace exemption must not apply.
      writeDart('pair.dart', '''
class Config {
  static const int retries = 3;
}

class Totals {
  static int sum = 0;
}
''');
      final findings = findingsOf(await run(), 'public classes').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('2 public classes'));
    });

    test('two unrelated public classes are still reported', () async {
      writePubspec();
      // A Set-wrapper and an independent DTO that never name each other: the
      // rule must still fire (coupling via shared free functions does not
      // exempt them under the strict class-to-class policy).
      writeDart('naming.dart', '''
class UsedNameIndex {
  UsedNameIndex(this.names);
  final Set<String> names;
}

class DeclaredOutputVariable {
  const DeclaredOutputVariable(this.name);
  final String name;
}

List<String> collect(UsedNameIndex index, DeclaredOutputVariable v) =>
    [v.name];
''');

      final findings = findingsOf(await run(), 'public classes').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('2 public classes'));
    });
  });

  // --- Constructor params (limit 8) ------------------------------------------

  group('constructor params (limit 8)', () {
    String classWithParams(String name, int params) {
      final ps = List.generate(params, (i) => 'this.p$i').join(', ');
      final fields =
          List.generate(params, (i) => '  final int p$i;').join('\n');
      return 'class $name {\n  $name($ps);\n$fields\n}\n';
    }

    test('a constructor with more than 8 params is reported', () async {
      writePubspec();
      writeDart('wide.dart', classWithParams('Wide', 9));

      final findings =
          findingsOf(await run(), 'parameters').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'constructor_params');
      expect(findings.single.message, contains('Constructor Wide has 9'));
      expect(findings.single.message, contains('limit: 8'));
    });

    test('a constructor with exactly 8 params is allowed', () async {
      writePubspec();
      writeDart('ok.dart', classWithParams('Ok', 8));
      expect(findingsOf(await run(), 'parameters'), isEmpty);
    });

    test('super.key does not count toward the limit', () async {
      writePubspec();
      // 8 real params + super.key = 9 formals, but key is widget boilerplate.
      final ps = List.generate(8, (i) => 'required this.p$i').join(', ');
      final fields = List.generate(8, (i) => '  final int p$i;').join('\n');
      writeDart('row.dart', '''
import 'package:flutter/material.dart';

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, $ps});
$fields
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');
      expect(findingsOf(await run(), 'parameters'), isEmpty);
    });

    test('a field formal named key still counts', () async {
      writePubspec();
      // Only `super.key` is exempt; a regular parameter that happens to be
      // called `key` is real API surface.
      final ps = List.generate(8, (i) => 'required this.p$i').join(', ');
      final fields = List.generate(8, (i) => '  final int p$i;').join('\n');
      // Non-const so the immutable-data-class exemption doesn't apply; the
      // point here is that only `super.key` is special, not the name `key`.
      writeDart('entry.dart', '''
class Entry {
  Entry({required this.key, $ps});
  final String key;
$fields
}
''');
      final findings = findingsOf(await run(), 'parameters').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('Constructor Entry has 9'));
    });
  });

  // --- Constructor param exemptions ------------------------------------------

  group('constructor param exemptions', () {
    String params(int n, {bool named = false}) => List.generate(
        n, (i) => named ? 'required this.p$i' : 'this.p$i').join(', ');
    String fields(int n) =>
        List.generate(n, (i) => '  final int p$i;').join('\n');

    test('a private named constructor is exempt', () async {
      writePubspec();
      writeDart('bindings.dart', '''
class Bindings {
  Bindings._(${params(10)});
${fields(10)}
}
''');
      expect(findingsOf(await run(), 'parameters'), isEmpty);
    });

    test('a constructor of a private class is exempt', () async {
      writePubspec();
      writeDart('hidden.dart', '''
class _Hidden {
  _Hidden(${params(10)});
${fields(10)}
}
''');
      expect(findingsOf(await run(), 'parameters'), isEmpty);
    });

    test('a const constructor of an immutable non-widget data class is exempt',
        () async {
      writePubspec();
      writeDart('anchor.dart', '''
class WindowAnchor {
  const WindowAnchor({${params(10, named: true)}});
${fields(10)}
}
''');
      expect(findingsOf(await run(), 'parameters'), isEmpty);
    });

    test('a non-const all-final class with copyWith is exempt', () async {
      writePubspec();
      // A state carrier whose initializer keeps the ctor non-const; copyWith
      // is the data-class marker that stands in for `const`.
      writeDart('state.dart', '''
class BuilderState {
  BuilderState({${params(10, named: true)}});
${fields(10)}
  BuilderState copyWith() => this;
}
''');
      expect(findingsOf(await run(), 'parameters'), isEmpty);
    });

    test('a non-const class without copyWith is still flagged', () async {
      writePubspec();
      // e.g. a service with many injected dependencies.
      writeDart('service.dart', '''
class Service {
  Service(${params(10)});
${fields(10)}
}
''');
      expect(findingsOf(await run(), 'parameters'), hasLength(1));
    });

    test('a wide const StatelessWidget constructor is still flagged',
        () async {
      writePubspec();
      // Widgets are also const + all-final; the widget exclusion is
      // load-bearing — a wide widget constructor is a composition smell.
      writeDart('wide_widget.dart', '''
import 'package:flutter/material.dart';

class WideWidget extends StatelessWidget {
  const WideWidget({super.key, ${params(10, named: true)}});
${fields(10)}
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');
      final findings = findingsOf(await run(), 'parameters').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('Constructor WideWidget has 10'));
    });

    test('a const class declaring build(BuildContext) is still flagged',
        () async {
      writePubspec();
      // Custom widget base the superclass set doesn't know.
      writeDart('custom_base.dart', '''
class Panel extends BasePanel {
  const Panel({${params(10, named: true)}});
${fields(10)}
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');
      expect(findingsOf(await run(), 'parameters'), hasLength(1));
    });

    test('a const constructor with a non-final field is still flagged',
        () async {
      writePubspec();
      // Invalid const (parse tolerates it) — mutable state means not a data
      // carrier, so no exemption.
      writeDart('mutable.dart', '''
class Mutable {
  const Mutable({${params(9, named: true)}, required this.count});
${fields(9)}
  int count = 0;
}
''');
      expect(findingsOf(await run(), 'parameters'), hasLength(1));
    });
  });

  // --- Part files --------------------------------------------------------------

  group('part files', () {
    test('public class count is not reported for part-of files', () async {
      writePubspec();
      writeDart('canvas.dart', '''
part 'canvas.edges.dart';

class Canvas {
  const Canvas();
}
''');
      writeDart('canvas.edges.dart', '''
part of 'canvas.dart';

class EdgeA {}

class EdgeB {}

class EdgeC {}
''');
      expect(findingsOf(await run(), 'public classes'), isEmpty);
    });

    test('method length is still reported inside part files', () async {
      writePubspec();
      writeDart('host.dart', "part 'host.impl.dart';\n");
      writeDart(
          'host.impl.dart', "part of 'host.dart';\n${functionWithLines('bigOne', 35)}");
      expect(findingsOf(await run(), 'bigOne'), hasLength(1));
    });

    test('file length is still reported for part files', () async {
      writePubspec();
      writeDart('lib_main.dart', "part 'lib_main.body.dart';\n");
      writeDart('lib_main.body.dart',
          "part of 'lib_main.dart';\n${fileWithLines(310)}");
      expect(findingsOf(await run(), 'File contains'), hasLength(1));
    });
  });

  // --- Folder file count (limit 15) ------------------------------------------

  group('folder file count (limit 15)', () {
    test('a folder with more than 15 Dart files is reported', () async {
      writePubspec();
      for (var i = 0; i < 16; i++) {
        writeDart('widgets/w$i.dart', 'final x$i = $i;\n');
      }

      final findings = findingsOf(await run(), 'Dart files').toList();
      expect(findings, hasLength(1));
      expect(findings.single.rule, 'folder_file_count');
      expect(findings.single.path, 'lib/widgets');
      expect(findings.single.message, contains('16 Dart files'));
      expect(findings.single.line, isNull);
    });

    test('a folder with exactly 15 Dart files is allowed', () async {
      writePubspec();
      for (var i = 0; i < 15; i++) {
        writeDart('widgets/w$i.dart', 'final x$i = $i;\n');
      }
      expect(findingsOf(await run(), 'Dart files'), isEmpty);
    });

    test('ignored/generated files do not count toward the folder total',
        () async {
      writePubspec();
      for (var i = 0; i < 15; i++) {
        writeDart('widgets/w$i.dart', 'final x$i = $i;\n');
      }
      // Two extra generated files would push the raw count to 17, but they are
      // excluded, so the folder stays at 15 and is not flagged.
      writeDart('widgets/w.g.dart', 'final g = 0;\n');
      writeDart('widgets/w.freezed.dart', 'final f = 0;\n');
      expect(findingsOf(await run(), 'Dart files'), isEmpty);
    });
  });

  // --- Generated-file exclusion ----------------------------------------------

  group('generated-file exclusion', () {
    test('default-ignored *.g.dart files are skipped', () async {
      writePubspec();
      writeDart('model.g.dart', fileWithLines(2000));
      expect((await run()).findings, isEmpty);
    });

    test('*.config.dart and *.pbserver.dart are skipped via local guard',
        () async {
      writePubspec();
      writeDart('injection.config.dart', fileWithLines(2000));
      writeDart('service.pbserver.dart', fileWithLines(2000));
      expect((await run()).findings, isEmpty);
    });

    test('user ignore patterns are honored', () async {
      writePubspec();
      writeConfig('ignore:\n  - "lib/legacy/**"\n');
      writeDart('legacy/old.dart', fileWithLines(2000));
      expect((await run()).findings, isEmpty);
    });
  });

  // --- Config-driven behavior ------------------------------------------------

  group('config', () {
    test('enabled: false yields an empty result', () async {
      writePubspec();
      writeConfig('maintainability:\n  enabled: false\n');
      writeDart('big.dart', fileWithLines(2000));

      final result = await run();
      expect(result.analyzerName, 'maintainability');
      expect(result.findings, isEmpty);
    });

    test('a custom lower limit is honored', () async {
      writePubspec();
      writeConfig('maintainability:\n  file_lines: 80\n');
      writeDart('mid.dart', fileWithLines(100)); // under default 300, over 80

      final findings = findingsOf(await run(), 'File contains').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('limit: 80'));
    });
  });

  // --- Finding shape ---------------------------------------------------------

  test('findings carry a per-metric rule and forward-slash paths', () async {
    writePubspec();
    writeDart('features/home/big.dart', fileWithLines(600));

    final finding = (await run()).findings.first;
    expect(finding.rule, 'file_length');
    expect(finding.path, 'lib/features/home/big.dart');
    expect(finding.path, isNot(contains(r'\')));
    expect(finding.recommendation, isNotNull);
  });
}
