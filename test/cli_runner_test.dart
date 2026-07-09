import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Quiet logger so command output does not clutter the test report.
  final logger = Logger(useColor: false);
  CliRunner runner() => CliRunner(logger: logger);

  test('version command returns exit code 0', () async {
    expect(await runner().run(['version']), 0);
  });

  test('unknown command returns usage exit code 64', () async {
    expect(await runner().run(['definitely-not-a-command']), 64);
  });

  test('--help returns exit code 0', () async {
    expect(await runner().run(['--help']), 0);
  });

  group('scan', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_cli_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns 0 for a valid project', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      Directory(p.join(tempDir.path, 'lib')).createSync();

      expect(await runner().run(['scan', '--path', tempDir.path]), 0);
    });

    test('returns 1 for an invalid project', () async {
      expect(await runner().run(['scan', '--path', tempDir.path]), 1);
    });
  });

  group('unused-assets', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_cli_');
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      Directory(p.join(tempDir.path, 'lib')).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns 0 (stub) for a valid project', () async {
      expect(await runner().run(['unused-assets', '--path', tempDir.path]), 0);
    });
  });

  group('duplicate-widgets', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_cli_');
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      Directory(p.join(tempDir.path, 'lib')).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns 0 for a valid project', () async {
      expect(
        await runner().run(['duplicate-widgets', '--path', tempDir.path]),
        0,
      );
    });

    test('returns 1 for an invalid project', () async {
      tempDir.deleteSync(recursive: true);
      tempDir.createSync();
      expect(
        await runner().run(['duplicate-widgets', '--path', tempDir.path]),
        1,
      );
    });
  });

  group('primary-constructors', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_cli_');
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      Directory(p.join(tempDir.path, 'lib')).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns 0 for a valid project', () async {
      expect(
        await runner().run(['primary-constructors', '--path', tempDir.path]),
        0,
      );
    });

    test('returns 1 for an invalid project', () async {
      tempDir.deleteSync(recursive: true);
      tempDir.createSync();
      expect(
        await runner().run(['primary-constructors', '--path', tempDir.path]),
        1,
      );
    });
  });

  group('all', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_cli_');
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      Directory(p.join(tempDir.path, 'lib')).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('runs every analyzer and returns 0 for a valid project', () async {
      expect(await runner().run(['all', '--path', tempDir.path]), 0);
    });

    test('returns 1 for an invalid project', () async {
      tempDir.deleteSync(recursive: true);
      tempDir.createSync();
      expect(await runner().run(['all', '--path', tempDir.path]), 1);
    });
  });
}
