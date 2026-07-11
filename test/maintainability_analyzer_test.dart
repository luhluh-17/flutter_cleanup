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
