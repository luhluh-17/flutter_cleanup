import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analysis/analysis_result.dart';
import '../analysis/analyzer.dart';
import '../analysis/path_utils.dart';
import '../models/finding.dart';
import '../models/project_paths.dart';
import '../services/ignore_service.dart';

/// Detects Dart files under `lib/` that are unreachable from `lib/main.dart`.
///
/// Builds an import/export/part graph from directives (no AST), then traverses
/// from `lib/main.dart`. Any `lib/**/*.dart` file not visited is reported as
/// likely unused. See the README for the v1 limitations (single entrypoint, no
/// reflection/codegen/routing awareness).
class UnusedFilesAnalyzer implements Analyzer {
  const UnusedFilesAnalyzer();

  static const String rule = 'unused_file';

  /// The reachability root, as a project-relative POSIX key.
  static const String _rootKey = 'lib/main.dart';

  /// Matches `import`/`export`/`part` directives and captures the URI. The
  /// quote required immediately after the keyword excludes `part of ...;`.
  static final RegExp _directive =
      RegExp(r'''^\s*(?:import|export|part)\s+(['"])([^'"]+)\1''',
          multiLine: true);

  @override
  String get name => 'unused-files';

  @override
  Future<AnalysisResult> analyze(ProjectPaths paths) async {
    final libDir = Directory(paths.libDir);
    if (!libDir.existsSync()) return AnalysisResult.empty(name);

    final ignore = IgnoreService.forProject(paths.root);

    // 1. Collect every Dart file under lib/ as a forward-slash key. Ignored
    //    files are excluded from the node set, so they neither participate in
    //    the graph (edges to them simply fall away) nor get reported. Note:
    //    ignoring lib/main.dart would remove the reachability root and disable
    //    analysis — the built-in defaults never match it.
    final all = <String>{
      for (final entity in libDir.listSync(recursive: true))
        if (entity is File && p.extension(entity.path) == '.dart')
          if (!ignore.isIgnored(toPosixRelative(paths.root, entity.path)))
            toPosixRelative(paths.root, entity.path),
    };

    // 2. Without the root, reachability is undefined — report nothing.
    if (!all.contains(_rootKey)) return AnalysisResult.empty(name);

    // 3. The package name lets us resolve self `package:<name>/...` imports.
    final packageName = _readPackageName(paths);

    // 4. Build adjacency, keeping only edges to files that exist under lib/.
    final edges = <String, List<String>>{};
    for (final key in all) {
      final file = File(p.join(paths.root, p.joinAll(key.split('/'))));
      final contents = file.readAsStringSync();
      final targets = <String>[];
      for (final match in _directive.allMatches(contents)) {
        final resolved = _resolve(key, match.group(2)!, packageName);
        if (resolved != null && all.contains(resolved)) {
          targets.add(resolved);
        }
      }
      edges[key] = targets;
    }

    // 5. Traverse from the root.
    final visited = <String>{};
    final queue = <String>[_rootKey];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) continue;
      queue.addAll(edges[current] ?? const []);
    }

    // 6. Anything not visited is unreachable.
    final unreachable = all.difference(visited).toList()..sort();
    final findings = [
      for (final key in unreachable)
        Finding(
          rule: rule,
          path: key,
          severity: Severity.warning,
          message: 'Dart file appears to be unreachable from lib/main.dart.',
        ),
    ];

    return AnalysisResult(analyzerName: name, findings: findings);
  }

  /// Resolves a directive [uri] (seen in file [fromKey]) to a `lib/...` key,
  /// or `null` if it points outside this package's `lib/`.
  String? _resolve(String fromKey, String uri, String? packageName) {
    if (uri.startsWith('dart:')) return null;

    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0) return null;
      final pkg = rest.substring(0, slash);
      if (packageName == null || pkg != packageName) return null;
      return p.url.normalize('lib/${rest.substring(slash + 1)}');
    }

    // Relative URI, resolved against the importing file's directory.
    return p.url.normalize(p.url.join(p.url.dirname(fromKey), uri));
  }

  /// Reads `name:` from `pubspec.yaml`, or `null` if unavailable.
  String? _readPackageName(ProjectPaths paths) {
    final file = File(paths.pubspec);
    if (!file.existsSync()) return null;
    final dynamic doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return null;
    final dynamic name = doc['name'];
    return name is String ? name : null;
  }
}
