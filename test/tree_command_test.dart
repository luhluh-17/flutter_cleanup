import 'dart:convert';
import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tree_command_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- Fixture helpers -------------------------------------------------------

  void writePubspec() {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
  }

  void mkdir(String rel) {
    Directory(p.join(tempDir.path, p.joinAll(rel.split('/'))))
        .createSync(recursive: true);
  }

  void writeIgnoreConfig(String contents) {
    File(p.join(tempDir.path, IgnoreService.configFileName))
        .writeAsStringSync(contents);
  }

  /// Runs the CLI with a file-backed logger and returns exit code + output.
  Future<({int exitCode, String raw})> run(List<String> args) async {
    final outFile = File(p.join(tempDir.path, 'out.txt'));
    final sink = outFile.openWrite();
    final logger = Logger(useColor: false, out: sink, err: sink);
    final exitCode = await CliRunner(logger: logger)
        .run(['tree', '--path', tempDir.path, ...args]);
    await sink.flush();
    await sink.close();
    return (exitCode: exitCode, raw: outFile.readAsStringSync());
  }

  Future<({int exitCode, Map<String, dynamic> json})> runJson(
    List<String> args,
  ) async {
    final result = await run(['--json', ...args]);
    return (
      exitCode: result.exitCode,
      json: jsonDecode(result.raw) as Map<String, dynamic>,
    );
  }

  List<String> childNames(Map<String, dynamic> node) => [
        for (final child in node['children'] as List<Object?>)
          (child as Map<String, dynamic>)['name'] as String,
      ];

  // --- Text mode -------------------------------------------------------------

  test('prints an ASCII tree of lib by default', () async {
    writePubspec();
    mkdir('lib/core');
    mkdir('lib/features/activities');
    mkdir('lib/features/workflow');
    mkdir('lib/initialization');

    final result = await run([]);

    expect(result.exitCode, 0);
    expect(
      result.raw,
      contains('lib\n'
          '├── core\n'
          '├── features\n'
          '│   ├── activities\n'
          '│   └── workflow\n'
          '└── initialization\n'),
    );
  });

  test('an empty lib prints just the root name', () async {
    writePubspec();
    mkdir('lib');

    final result = await run([]);

    expect(result.exitCode, 0);
    expect(result.raw, endsWith('\nlib\n'));
  });

  test('--root changes the tree root', () async {
    writePubspec();
    mkdir('lib/features/activities');

    final result = await run(['--root', 'lib/features']);

    expect(result.exitCode, 0);
    expect(result.raw, contains('lib/features\n└── activities\n'));
  });

  test('fails validation when the project is not a Flutter project', () async {
    mkdir('lib');

    final result = await run([]);

    expect(result.exitCode, 1);
    expect(result.raw, contains('pubspec.yaml not found'));
  });

  test('errors when --root does not exist', () async {
    writePubspec();
    mkdir('lib');

    final result = await run(['--root', 'lib/missing']);

    expect(result.exitCode, 1);
    expect(result.raw, contains('Directory not found: lib/missing'));
  });

  test('rejects a non-integer --depth with a usage error', () async {
    writePubspec();
    mkdir('lib');

    expect((await run(['--depth', 'abc'])).exitCode, 64);
    expect((await run(['--depth', '0'])).exitCode, 64);
  });

  test('rejects a --root outside the project with a usage error', () async {
    writePubspec();
    mkdir('lib');

    expect((await run(['--root', '../elsewhere'])).exitCode, 64);
  });

  // --- JSON mode -------------------------------------------------------------

  test('--json emits the schemaVersion/root/children document', () async {
    writePubspec();
    mkdir('lib/core');
    mkdir('lib/features/activities');

    final result = await runJson([]);

    expect(result.exitCode, 0);
    expect(result.json, {
      'schemaVersion': 1,
      'root': 'lib',
      'children': [
        {'name': 'core', 'children': <Object?>[]},
        {
          'name': 'features',
          'children': [
            {'name': 'activities', 'children': <Object?>[]},
          ],
        },
      ],
    });
  });

  test('--json with an empty lib emits empty children', () async {
    writePubspec();
    mkdir('lib');

    final result = await runJson([]);

    expect(result.exitCode, 0);
    expect(result.json,
        {'schemaVersion': 1, 'root': 'lib', 'children': <Object?>[]});
  });

  test('--depth limits the JSON tree', () async {
    writePubspec();
    mkdir('lib/features/activities/widgets');

    final result = await runJson(['--depth', '1']);

    expect(result.exitCode, 0);
    expect(childNames(result.json), ['features']);
    final features =
        (result.json['children'] as List<Object?>).single as Map<String, dynamic>;
    expect(features['children'], isEmpty);
  });

  test('IgnoreService config excludes directories', () async {
    writePubspec();
    mkdir('lib/core');
    mkdir('lib/generated/proto');
    writeIgnoreConfig('ignore:\n  - "lib/generated"\n');

    final result = await runJson([]);

    expect(result.exitCode, 0);
    expect(childNames(result.json), ['core']);
  });

  test('--json error document is emitted for a missing root', () async {
    writePubspec();
    mkdir('lib');

    final result = await runJson(['--root', 'lib/missing']);

    expect(result.exitCode, 1);
    expect(result.json['schemaVersion'], 1);
    expect((result.json['error'] as Map<String, dynamic>)['message'],
        'Directory not found: lib/missing');
  });
}
