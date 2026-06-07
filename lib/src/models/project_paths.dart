import 'package:path/path.dart' as p;

/// Thrown when a `--path` value cannot be resolved to a usable project root.
///
/// The most common trigger is a Windows path whose backslashes were stripped by
/// a bash-style shell (e.g. `C:\Users\me\app` arriving as `C:Usersmeapp`), which
/// leaves a drive-relative path that cannot be recovered. Rather than silently
/// joining the mangled string onto the current directory, [ProjectPaths] raises
/// this with an actionable message.
class InvalidProjectPathException implements Exception {
  InvalidProjectPathException(this.message);

  /// Human-readable explanation, suitable for printing directly to the user.
  final String message;

  @override
  String toString() => message;
}

/// Resolves and holds the well-known paths of a Flutter project rooted at
/// [root].
///
/// Centralizing path resolution here keeps file-system conventions in one
/// place so future analyzers can reuse them instead of re-deriving paths.
class ProjectPaths {
  /// Resolves [input] to an absolute, normalized project [root].
  ///
  /// A relative input is resolved against the current directory; an absolute
  /// input is used as-is. [context] defaults to the host platform's path
  /// context and exists mainly so tests can pin Windows vs POSIX semantics.
  ///
  /// Throws [InvalidProjectPathException] when [input] looks like a Windows
  /// path that lost its separators (see [_driveRelative]).
  factory ProjectPaths(String input, {p.Context? context}) {
    final ctx = context ?? p.context;
    return ProjectPaths._(ctx, _resolveRoot(input, ctx));
  }

  ProjectPaths._(this._context, this.root);

  final p.Context _context;

  /// The absolute, normalized project root directory.
  final String root;

  /// Matches a Windows drive letter (`C:`) that is *not* followed by a path
  /// separator — a drive-relative path. In practice this almost always means an
  /// absolute path lost its `\` separators while passing through a bash-style
  /// shell, so it is treated as an error rather than resolved against the cwd.
  static final RegExp _driveRelative = RegExp(r'^[A-Za-z]:(?![\\/])');

  static String _resolveRoot(String input, p.Context context) {
    if (context.style == p.Style.windows && _driveRelative.hasMatch(input)) {
      throw InvalidProjectPathException(
        'The path "$input" looks like a Windows path that lost its directory '
        'separators (a drive letter not followed by "\\" or "/").\n'
        'This usually happens when an unquoted back-slashed path is passed '
        'through a bash-style shell. Quote the path or use forward slashes:\n'
        '  --path "C:/Users/you/my_app"',
      );
    }
    return context.normalize(
      context.isAbsolute(input) ? input : context.join(context.current, input),
    );
  }

  /// Absolute path to the project's `pubspec.yaml`.
  String get pubspec => _context.join(root, 'pubspec.yaml');

  /// Absolute path to the project's `lib/` directory.
  String get libDir => _context.join(root, 'lib');

  /// Absolute path to the conventional application entrypoint, `lib/main.dart`.
  String get mainEntrypoint => _context.join(libDir, 'main.dart');

  /// Absolute path to the project's `assets/` directory.
  String get assetsDir => _context.join(root, 'assets');
}
