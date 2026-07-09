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

  /// Writes a `.flutter_cleanup.yaml` in the project root.
  void writeConfig(String contents) {
    File(p.join(tempDir.path, '.flutter_cleanup.yaml'))
        .writeAsStringSync(contents);
  }

  Future<AnalysisResult> run() =>
      const MaintainabilityAnalyzer().analyze(ProjectPaths(tempDir.path));

  Iterable<Finding> findingsOf(AnalysisResult r, String messageSubstring) =>
      r.findings.where((f) => f.message.contains(messageSubstring));

  /// A file with exactly [lines] lines of code (one top-level declaration per
  /// line). Real code — not comments — because comment-only lines no longer
  /// count toward the file-length metric.
  String fileWithLines(int lines) {
    final buffer = StringBuffer();
    for (var i = 0; i < lines; i++) {
      buffer.writeln('final v$i = $i;');
    }
    return buffer.toString();
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

  // --- Rule 1: file length ---------------------------------------------------

  group('file length', () {
    test('over the warning threshold reports a warning', () async {
      writePubspec();
      writeDart('big.dart', fileWithLines(600)); // default warning 500

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings, hasLength(1));
      expect(findings.single.severity, Severity.warning);
      expect(findings.single.message, contains('600 lines'));
      expect(findings.single.recommendation, isNotNull);
    });

    test('over the error threshold reports an error', () async {
      writePubspec();
      writeDart('huge.dart', fileWithLines(1100)); // default error 1000

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings.single.severity, Severity.error);
    });

    test('a small file produces no file-length finding', () async {
      writePubspec();
      writeDart('small.dart', fileWithLines(100));

      expect(findingsOf(await run(), 'lines'), isEmpty);
    });

    test('blank lines are not counted', () async {
      writePubspec();
      // 400 code lines + 400 blank lines = 800 raw, 400 counted (< 500).
      final buffer = StringBuffer();
      for (var i = 0; i < 400; i++) {
        buffer.writeln('final v$i = $i;');
        buffer.writeln();
      }
      writeDart('padded.dart', buffer.toString());

      expect(findingsOf(await run(), 'lines'), isEmpty);
    });

    test('comment-only lines are not counted', () async {
      writePubspec();
      // 600 comment lines + 100 code lines: only the 100 code lines count,
      // which is under the default warning threshold of 500.
      final buffer = StringBuffer();
      for (var i = 0; i < 600; i++) {
        buffer.writeln('// documentation line $i');
      }
      for (var i = 0; i < 100; i++) {
        buffer.writeln('final v$i = $i;');
      }
      writeDart('documented.dart', buffer.toString());

      expect(findingsOf(await run(), 'lines'), isEmpty);
    });

    test('a trailing comment after code still counts the line', () async {
      writePubspec();
      // 600 code lines, each with a trailing comment — all 600 count (> 500).
      final buffer = StringBuffer();
      for (var i = 0; i < 600; i++) {
        buffer.writeln('final v$i = $i; // note $i');
      }
      writeDart('trailing.dart', buffer.toString());

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('600 lines'));
    });

    test('the finding message shows the accepted limit range', () async {
      writePubspec();
      writeDart('big.dart', fileWithLines(600)); // default 500 / 1000

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings.single.message, contains('limit: 500–1000'));
    });
  });

  // --- Rule 2: method length -------------------------------------------------

  group('method length', () {
    test('a long method is reported', () async {
      writePubspec();
      writeDart('svc.dart', functionWithLines('generateMonthlyReport', 80));

      final findings =
          findingsOf(await run(), 'generateMonthlyReport()').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('Method generateMonthlyReport()'));
      expect(findings.single.message, contains('limit: 50–100'));
      expect(findings.single.severity, Severity.warning);
    });

    test('getters, setters and constructors are ignored', () async {
      writePubspec();
      final body = List.generate(80, (i) => '    var v$i = $i;').join('\n');
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

      // None of getter/setter/constructor should produce a method-length issue.
      expect(findingsOf(await run(), 'Method'), isEmpty);
    });
  });

  // --- Rule 3: build() length ------------------------------------------------

  group('build() length', () {
    test('a long build() is reported as a build finding', () async {
      writePubspec();
      final body = List.generate(120, (i) => '    final w$i = $i;').join('\n');
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
      expect(build.single.message, contains('build() method contains'));
      expect(build.single.severity, Severity.warning); // 100 < n < 200
      // It must not also be reported as a generic "Method build()".
      expect(findingsOf(result, 'Method build()'), isEmpty);
    });
  });

  // --- Rule 4: widget count --------------------------------------------------

  group('widget count', () {
    String widgetClass(String name, String base) => '''
class $name extends $base {
  const $name({super.key});
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''';

    test('a file over the threshold is reported', () async {
      writePubspec();
      const bases = [
        'StatelessWidget',
        'ConsumerWidget',
        'HookWidget',
        'HookConsumerWidget',
      ];
      final buffer = StringBuffer("import 'package:flutter/material.dart';\n");
      for (var i = 0; i < 11; i++) {
        buffer.writeln(widgetClass('W$i', bases[i % bases.length]));
      }
      writeDart('dashboard_page.dart', buffer.toString());

      final findings = findingsOf(await run(), 'widget classes').toList();
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('11 widget classes'));
    });

    test('a file below the threshold is not reported', () async {
      writePubspec();
      final buffer = StringBuffer("import 'package:flutter/material.dart';\n");
      for (var i = 0; i < 9; i++) {
        buffer.writeln(widgetClass('W$i', 'StatelessWidget'));
      }
      writeDart('ok.dart', buffer.toString());

      expect(findingsOf(await run(), 'widget classes'), isEmpty);
    });

    test('exactly at the threshold is reported (inclusive)', () async {
      writePubspec();
      final buffer = StringBuffer("import 'package:flutter/material.dart';\n");
      for (var i = 0; i < 10; i++) {
        buffer.writeln(widgetClass('W$i', 'StatelessWidget'));
      }
      writeDart('boundary.dart', buffer.toString());

      final findings = findingsOf(await run(), 'widget classes').toList();
      expect(findings.single.severity, Severity.warning);
    });
  });

  // --- Rule 5: nesting depth -------------------------------------------------

  group('nesting depth', () {
    test('a deeply nested widget tree is reported', () async {
      writePubspec();
      // Column > Container > Card > Padding > Row > Expanded > Center > Text = 8.
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
      expect(findings.single.message, contains('Maximum widget nesting depth is 8'));
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

  // --- Threshold boundaries --------------------------------------------------

  group('threshold boundaries', () {
    test('value exactly at warning emits a warning', () async {
      writePubspec();
      writeConfig('maintainability:\n  file_lines: { warning: 50, error: 100 }\n');
      writeDart('exact.dart', fileWithLines(50));

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings.single.severity, Severity.warning);
    });

    test('one below warning emits nothing', () async {
      writePubspec();
      writeConfig('maintainability:\n  file_lines: { warning: 50, error: 100 }\n');
      writeDart('below.dart', fileWithLines(49));

      expect(findingsOf(await run(), 'lines'), isEmpty);
    });

    test('value exactly at error emits an error', () async {
      writePubspec();
      writeConfig('maintainability:\n  file_lines: { warning: 50, error: 100 }\n');
      writeDart('err.dart', fileWithLines(100));

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings.single.severity, Severity.error);
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

    test('custom lower threshold is honored', () async {
      writePubspec();
      writeConfig('maintainability:\n  file_lines: { warning: 80, error: 160 }\n');
      writeDart('mid.dart', fileWithLines(100)); // under default 500, over 80

      final findings = findingsOf(await run(), 'lines').toList();
      expect(findings.single.severity, Severity.warning);
    });
  });

  // --- Finding shape ---------------------------------------------------------

  test('findings carry the maintainability rule and forward-slash paths',
      () async {
    writePubspec();
    writeDart('features/home/big.dart', fileWithLines(600));

    final finding = (await run()).findings.first;
    expect(finding.rule, 'maintainability');
    expect(finding.path, 'lib/features/home/big.dart');
    expect(finding.path, isNot(contains(r'\')));
    expect(finding.recommendation, isNotNull);
  });
}
