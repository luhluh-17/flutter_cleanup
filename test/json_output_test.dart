import 'dart:convert';
import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_json_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Writes a minimal valid Flutter project (pubspec + lib/) into [tempDir].
  void writeValidProject() {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    Directory(p.join(tempDir.path, 'lib')).createSync();
  }

  /// Runs [args] with a file-backed logger and returns the (exitCode, decoded
  /// JSON, raw output). Using a real [File] sink avoids hand-rolling [IOSink].
  Future<({int exitCode, Object? json, String raw})> runJson(
    List<String> args,
  ) async {
    final outFile = File(p.join(tempDir.path, 'out.json'));
    final sink = outFile.openWrite();
    final logger = Logger(useColor: false, out: sink, err: sink);
    final exitCode = await CliRunner(logger: logger).run(args);
    await sink.flush();
    await sink.close();

    final raw = outFile.readAsStringSync();
    return (exitCode: exitCode, json: jsonDecode(raw), raw: raw);
  }

  group('single-analyzer JSON', () {
    setUp(writeValidProject);

    for (final analyzer in const [
      'unused-assets',
      'unused-files',
      'duplicate-code',
      'duplicate-widgets',
      'maintainability',
      'primary-constructors',
      'architecture',
    ]) {
      test('$analyzer --json emits a valid single-analyzer document', () async {
        final result =
            await runJson([analyzer, '--json', '--path', tempDir.path]);

        expect(result.exitCode, 0);
        expect(result.raw.trimLeft(), startsWith('{'),
            reason: 'no banners or ANSI before the JSON document');

        final json = result.json as Map<String, dynamic>;
        expect(json['schemaVersion'], 1);
        expect(json['analyzer'], analyzer);
        expect(json['findings'], isA<List<Object?>>());
      });
    }
  });

  group('all command JSON aggregation', () {
    setUp(writeValidProject);

    test('all --json emits a single aggregate document', () async {
      final result = await runJson(['all', '--json', '--path', tempDir.path]);

      expect(result.exitCode, 0);
      expect(result.raw.trimLeft(), startsWith('{'));

      final json = result.json as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);

      final results = json['results'] as List<Object?>;
      expect(results, hasLength(7));
      expect(
        results
            .map((r) => (r as Map<String, dynamic>)['analyzer'])
            .toList(),
        [
          'unused-assets',
          'unused-files',
          'duplicate-code',
          'duplicate-widgets',
          'maintainability',
          'primary-constructors',
          'architecture',
        ],
      );
      for (final entry in results.cast<Map<String, dynamic>>()) {
        expect(entry['findings'], isA<List<Object?>>());
        expect(entry.containsKey('schemaVersion'), isFalse,
            reason: 'nested results do not repeat schemaVersion');
      }
    });
  });

  group('Finding serialization', () {
    test('omits optional fields when unset (byte-compatible with v1)', () {
      const finding = Finding(
        rule: 'unused_asset',
        path: 'assets/x.png',
        severity: Severity.warning,
        message: 'unused',
      );
      expect(finding.toJson(), {
        'rule': 'unused_asset',
        'path': 'assets/x.png',
        'severity': 'warning',
        'message': 'unused',
      });
    });

    test('includes line/column/confidence when set', () {
      const finding = Finding(
        rule: 'ARCH101',
        path: 'lib/x.dart',
        severity: Severity.error,
        message: 'bad import',
        line: 12,
        column: 3,
        confidence: Confidence.medium,
      );
      final json = finding.toJson();
      expect(json['line'], 12);
      expect(json['column'], 3);
      expect(json['confidence'], 'medium');
    });
  });

  group('validation failure JSON', () {
    test('emits a structured error object and exits 1', () async {
      // Empty dir: no pubspec.yaml, no lib/ — validation fails.
      final result = await runJson(['all', '--json', '--path', tempDir.path]);

      expect(result.exitCode, 1);

      final json = result.json as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);
      final error = json['error'] as Map<String, dynamic>;
      expect(error['message'], isA<String>());
      expect(error['message'], isNotEmpty);
    });
  });
}
