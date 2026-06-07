import 'package:path/path.dart' as p;

/// Resolves and holds the well-known paths of a Flutter project rooted at
/// [root].
///
/// Centralizing path resolution here keeps file-system conventions in one
/// place so future analyzers can reuse them instead of re-deriving paths.
class ProjectPaths {
  ProjectPaths(String root) : root = p.normalize(p.absolute(root));

  /// The absolute, normalized project root directory.
  final String root;

  /// Absolute path to the project's `pubspec.yaml`.
  String get pubspec => p.join(root, 'pubspec.yaml');

  /// Absolute path to the project's `lib/` directory.
  String get libDir => p.join(root, 'lib');

  /// Absolute path to the conventional application entrypoint, `lib/main.dart`.
  String get mainEntrypoint => p.join(libDir, 'main.dart');

  /// Absolute path to the project's `assets/` directory.
  String get assetsDir => p.join(root, 'assets');
}
