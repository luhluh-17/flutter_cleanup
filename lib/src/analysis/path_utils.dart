import 'package:path/path.dart' as p;

/// Converts an absolute [filePath] into a project-relative path using forward
/// slashes, relative to [root].
///
/// Using forward slashes everywhere keeps path comparisons stable across
/// Windows, macOS, and Linux (the filesystem may report native separators,
/// but pubspec entries and Dart `import`/`export` URIs always use `/`).
String toPosixRelative(String root, String filePath) {
  final relative = p.relative(filePath, from: root);
  return p.split(relative).join('/');
}
