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
    expect(config.widgetFileLines, 250);
    expect(config.controllerLines, 300);
    expect(config.fileLines, 300);
    expect(config.buildMethodLines, 60);
    expect(config.methodLines, 30);
    expect(config.widgetNestingDepth, 5);
    expect(config.maxPublicClasses, 1);
    expect(config.constructorParams, 8);
    expect(config.folderFiles, 15);
  });

  test('absent maintainability section yields defaults', () {
    writeConfig('architecture:\n  top_level: [config]\n');
    expect(load().widgetFileLines, 250);
  });

  test('malformed YAML falls back to defaults', () {
    writeConfig('maintainability: : : not valid');
    expect(load().widgetFileLines, 250);
  });

  test('enabled flag is parsed', () {
    writeConfig('maintainability:\n  enabled: false\n');
    expect(load().enabled, isFalse);
  });

  test('full override is applied', () {
    writeConfig('''
maintainability:
  widget_file_lines: 200
  controller_lines: 250
  file_lines: 220
  build_method_lines: 40
  method_lines: 20
  widget_nesting_depth: 4
  max_public_classes: 2
  constructor_params: 6
  folder_files: 10
''');
    final config = load();
    expect(config.widgetFileLines, 200);
    expect(config.controllerLines, 250);
    expect(config.fileLines, 220);
    expect(config.buildMethodLines, 40);
    expect(config.methodLines, 20);
    expect(config.widgetNestingDepth, 4);
    expect(config.maxPublicClasses, 2);
    expect(config.constructorParams, 6);
    expect(config.folderFiles, 10);
  });

  test('partial override keeps other metrics at their defaults', () {
    // Only method_lines is set; everything else stays default.
    writeConfig('maintainability:\n  method_lines: 20\n');
    final config = load();
    expect(config.methodLines, 20);
    expect(config.widgetFileLines, 250); // untouched metric stays default
    expect(config.constructorParams, 8);
  });

  test('wrong-typed values fall back to defaults', () {
    writeConfig('maintainability:\n  method_lines: "lots"\n');
    expect(load().methodLines, 30);
  });
}
