import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_archcfg_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ArchitectureConfig load(String? yaml) {
    if (yaml != null) {
      File(p.join(tempDir.path, ArchitectureConfig.configFileName))
          .writeAsStringSync(yaml);
    }
    return ArchitectureConfig.forProject(tempDir.path);
  }

  test('a missing config file yields the empty config', () {
    final config = load(null);
    expect(config.extraSublayers, isEmpty);
    expect(config.extraTopLevelDirs, isEmpty);
  });

  test('reads sublayers and top_level', () {
    final config = load('architecture:\n'
        '  sublayers:\n'
        '    presentation: [styles, painters]\n'
        '    data: [adapters]\n'
        '  top_level: [config]\n');

    expect(config.extraSublayers['presentation'], {'styles', 'painters'});
    expect(config.extraSublayers['data'], {'adapters'});
    expect(config.extraTopLevelDirs, {'config'});
  });

  test('ignores the unrelated ignore: section', () {
    final config = load('ignore:\n  - "lib/generated/**"\n');
    expect(config.extraSublayers, isEmpty);
    expect(config.extraTopLevelDirs, isEmpty);
  });

  test('tolerates wrong types without throwing', () {
    final config = load('architecture:\n'
        '  sublayers: not-a-map\n'
        '  top_level: 42\n');
    expect(config.extraSublayers, isEmpty);
    expect(config.extraTopLevelDirs, isEmpty);
  });

  test('keeps only string entries', () {
    final config = load('architecture:\n'
        '  sublayers:\n'
        '    presentation: [styles, 7, null]\n'
        '  top_level: [config, 9]\n');
    expect(config.extraSublayers['presentation'], {'styles'});
    expect(config.extraTopLevelDirs, {'config'});
  });

  test('malformed YAML falls back to empty', () {
    final config = load('architecture: : :\n  bad');
    expect(config.extraSublayers, isEmpty);
    expect(config.extraTopLevelDirs, isEmpty);
  });
}
