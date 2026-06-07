import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unused_files_test_');
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

  Future<AnalysisResult> run() =>
      const UnusedFilesAnalyzer().analyze(ProjectPaths(tempDir.path));

  Set<String> unusedPaths(AnalysisResult result) =>
      result.findings.map((f) => f.path).toSet();

  // --- Tests -----------------------------------------------------------------

  test('a project with only main.dart has no findings', () async {
    writePubspec();
    writeDart('main.dart', 'void main() {}');

    expect((await run()).findings, isEmpty);
  });

  test('relative import is reachable; unimported sibling is flagged', () async {
    writePubspec();
    writeDart('main.dart', "import 'used.dart';\nvoid main() {}");
    writeDart('used.dart', 'class Used {}');
    writeDart('orphan.dart', 'class Orphan {}');

    expect(unusedPaths(await run()), {'lib/orphan.dart'});
  });

  test('self package: import resolves to a lib file', () async {
    writePubspec(name: 'sample');
    writeDart('main.dart', "import 'package:sample/used.dart';\nvoid main() {}");
    writeDart('used.dart', 'class Used {}');

    expect((await run()).findings, isEmpty);
  });

  test('export edges are followed', () async {
    writePubspec();
    writeDart('main.dart', "import 'barrel.dart';\nvoid main() {}");
    writeDart('barrel.dart', "export 'leaf.dart';");
    writeDart('leaf.dart', 'class Leaf {}');

    expect((await run()).findings, isEmpty);
  });

  test('part directives are followed', () async {
    writePubspec();
    writeDart('main.dart', "part 'main_part.dart';\nvoid main() {}");
    writeDart('main_part.dart', "part of 'main.dart';");

    expect((await run()).findings, isEmpty);
  });

  test('transitive chain a -> b -> c is fully reachable', () async {
    writePubspec();
    writeDart('main.dart', "import 'a.dart';\nvoid main() {}");
    writeDart('a.dart', "import 'b.dart';");
    writeDart('b.dart', "import 'c.dart';");
    writeDart('c.dart', 'class C {}');

    expect((await run()).findings, isEmpty);
  });

  test('an unreachable cluster is entirely flagged', () async {
    writePubspec();
    writeDart('main.dart', 'void main() {}');
    writeDart('x.dart', "import 'y.dart';");
    writeDart('y.dart', "import 'x.dart';");

    expect(unusedPaths(await run()), {'lib/x.dart', 'lib/y.dart'});
  });

  test('parent-relative (../) imports resolve correctly', () async {
    writePubspec();
    writeDart('main.dart', "import 'src/feature.dart';\nvoid main() {}");
    writeDart('src/feature.dart', "import '../shared.dart';");
    writeDart('shared.dart', 'class Shared {}');

    expect((await run()).findings, isEmpty);
  });

  test('dart: and third-party package imports are ignored', () async {
    writePubspec();
    writeDart('main.dart', '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'used.dart';
void main() {}
''');
    writeDart('used.dart', 'class Used {}');

    expect((await run()).findings, isEmpty);
  });

  test('findings are forward-slash keyed and correctly shaped', () async {
    writePubspec();
    writeDart('main.dart', 'void main() {}');
    writeDart('src/widgets/orphan.dart', 'class Orphan {}');

    final result = await run();
    expect(result.analyzerName, 'unused-files');
    final finding = result.findings.single;
    expect(finding.path, 'lib/src/widgets/orphan.dart');
    expect(finding.path, isNot(contains(r'\')));
    expect(finding.rule, 'unused_file');
    expect(finding.severity, Severity.warning);
    expect(finding.message,
        'Dart file appears to be unreachable from lib/main.dart.');
  });

  test('missing lib/main.dart yields an empty result', () async {
    writePubspec();
    writeDart('app.dart', 'void main() {}');
    writeDart('helper.dart', 'class Helper {}');

    final result = await run();
    expect(result.findings, isEmpty);
  });
}
