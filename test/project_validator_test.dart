import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ProjectPaths pathsFor() => ProjectPaths(tempDir.path);

  void createPubspec() =>
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
  void createLib() => Directory(p.join(tempDir.path, 'lib')).createSync();
  void createAssets() => Directory(p.join(tempDir.path, 'assets')).createSync();

  const validator = ProjectValidator();

  test('reports errors when pubspec.yaml and lib are missing', () {
    final report = validator.validate(pathsFor());

    expect(report.hasErrors, isTrue);
    expect(
      report.results.where((r) => r.severity == ValidationSeverity.error),
      hasLength(2),
    );
  });

  test('passes when pubspec.yaml and lib exist, warns on missing assets', () {
    createPubspec();
    createLib();

    final report = validator.validate(pathsFor());

    expect(report.hasErrors, isFalse);
    expect(report.hasWarnings, isTrue, reason: 'assets/ is absent');
  });

  test('passes cleanly when assets directory is present', () {
    createPubspec();
    createLib();
    createAssets();

    final report = validator.validate(pathsFor());

    expect(report.hasErrors, isFalse);
    expect(report.hasWarnings, isFalse);
  });

  test('errors when only lib is missing', () {
    createPubspec();

    final report = validator.validate(pathsFor());

    expect(report.hasErrors, isTrue);
    expect(
      report.results.singleWhere((r) => r.label.contains('lib/')).severity,
      ValidationSeverity.error,
    );
  });
}
