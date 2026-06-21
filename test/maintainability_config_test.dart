import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('maintainability_config_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void writeConfig(String contents) {
    File(p.join(tempDir.path, '.flutter_cleanup.yaml'))
        .writeAsStringSync(contents);
  }

  MaintainabilityConfig load() =>
      MaintainabilityConfig.forProject(tempDir.path);

  test('absent config file yields all defaults', () {
    final config = load();
    expect(config.enabled, isTrue);
    expect(config.fileLines.warning, 500);
    expect(config.fileLines.error, 1000);
    expect(config.methodLines.warning, 50);
    expect(config.buildMethodLines.error, 200);
    expect(config.widgetCount.warning, 10);
    expect(config.widgetNestingDepth.error, 10);
  });

  test('absent maintainability section yields defaults', () {
    writeConfig('architecture:\n  top_level: [config]\n');
    expect(load().fileLines.warning, 500);
  });

  test('malformed YAML falls back to defaults', () {
    writeConfig('maintainability: : : not valid');
    expect(load().fileLines.warning, 500);
  });

  test('enabled flag is parsed', () {
    writeConfig('maintainability:\n  enabled: false\n');
    expect(load().enabled, isFalse);
  });

  test('full override is applied', () {
    writeConfig('''
maintainability:
  file_lines: { warning: 200, error: 400 }
  method_lines: { warning: 30, error: 60 }
  build_method_lines: { warning: 80, error: 160 }
  widget_count: { warning: 5, error: 12 }
  widget_nesting_depth: { warning: 4, error: 8 }
''');
    final config = load();
    expect(config.fileLines.warning, 200);
    expect(config.fileLines.error, 400);
    expect(config.methodLines.warning, 30);
    expect(config.buildMethodLines.warning, 80);
    expect(config.widgetCount.error, 12);
    expect(config.widgetNestingDepth.warning, 4);
  });

  test('partial override keeps other bounds at their defaults', () {
    // Only file_lines.warning is set; everything else stays default.
    writeConfig('maintainability:\n  file_lines: { warning: 250 }\n');
    final config = load();
    expect(config.fileLines.warning, 250);
    expect(config.fileLines.error, 1000); // default preserved
    expect(config.methodLines.warning, 50); // untouched metric stays default
  });

  test('wrong-typed values fall back to defaults', () {
    writeConfig('maintainability:\n  file_lines: { warning: "lots" }\n');
    expect(load().fileLines.warning, 500);
  });
}
