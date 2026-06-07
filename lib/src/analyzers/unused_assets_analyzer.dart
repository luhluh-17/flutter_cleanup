import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analysis/analysis_result.dart';
import '../analysis/analyzer.dart';
import '../models/finding.dart';
import '../models/project_paths.dart';

/// Detects assets declared in a Flutter project's `pubspec.yaml` that are
/// never referenced from Dart source under `lib/`.
///
/// The detection is intentionally simple (no AST): an asset counts as used
/// when its project-relative path appears as a quoted string literal anywhere
/// in `lib/**`. This minimizes false positives — it will not wrongly flag a
/// referenced asset for removal — at the cost of some false negatives (see the
/// limitations noted on the individual steps).
class UnusedAssetsAnalyzer implements Analyzer {
  const UnusedAssetsAnalyzer();

  static const String rule = 'unused_asset';

  @override
  String get name => 'unused-assets';

  @override
  Future<AnalysisResult> analyze(ProjectPaths paths) async {
    final declaredDirs = _declaredAssetDirs(paths);
    final assetFiles = _discoverAssetFiles(paths, declaredDirs);
    final referenced = _collectDartStringLiterals(paths);

    final findings = <Finding>[
      for (final asset in assetFiles)
        if (!referenced.contains(asset))
          Finding(
            rule: rule,
            path: asset,
            severity: Severity.warning,
            message: 'Asset appears to be unused.',
          ),
    ];

    return AnalysisResult(analyzerName: name, findings: findings);
  }

  /// Reads `flutter > assets` from `pubspec.yaml` and returns the
  /// directory-style entries (those ending in `/`).
  ///
  /// Single-file entries (e.g. `assets/images/logo.png`) are ignored for now.
  List<String> _declaredAssetDirs(ProjectPaths paths) {
    final file = File(paths.pubspec);
    if (!file.existsSync()) return const [];

    final dynamic doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return const [];

    final dynamic flutter = doc['flutter'];
    if (flutter is! YamlMap) return const [];

    final dynamic assets = flutter['assets'];
    if (assets is! YamlList) return const [];

    return [
      for (final dynamic entry in assets)
        if (entry is String && entry.endsWith('/')) entry,
    ];
  }

  /// Recursively collects every file under each declared asset directory,
  /// returning their project-relative POSIX paths. Missing directories are
  /// skipped.
  List<String> _discoverAssetFiles(
    ProjectPaths paths,
    List<String> declaredDirs,
  ) {
    final files = <String>[];
    for (final dir in declaredDirs) {
      final absDir = Directory(p.join(paths.root, p.normalize(dir)));
      if (!absDir.existsSync()) continue;

      for (final entity in absDir.listSync(recursive: true)) {
        if (entity is File) {
          files.add(_toPosixRelative(paths.root, entity.path));
        }
      }
    }
    return files;
  }

  /// Reads every `*.dart` file under `lib/` and returns the set of quoted
  /// string literals found (both single- and double-quoted).
  Set<String> _collectDartStringLiterals(ProjectPaths paths) {
    final libDir = Directory(paths.libDir);
    if (!libDir.existsSync()) return const {};

    final literals = <String>{};
    final singleQuoted = RegExp(r"'([^']*)'");
    final doubleQuoted = RegExp(r'"([^"]*)"');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.dart') continue;

      final contents = entity.readAsStringSync();
      for (final match in singleQuoted.allMatches(contents)) {
        literals.add(match.group(1)!);
      }
      for (final match in doubleQuoted.allMatches(contents)) {
        literals.add(match.group(1)!);
      }
    }
    return literals;
  }

  /// Converts an absolute file path into a project-relative path using forward
  /// slashes, so comparisons are stable across Windows, macOS, and Linux.
  String _toPosixRelative(String root, String filePath) {
    final relative = p.relative(filePath, from: root);
    return p.split(relative).join('/');
  }
}
