import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Decides which project files analyzers should exclude from analysis.
///
/// This is the single authority for ignore configuration: analyzers ask
/// [isIgnored] and never parse the config themselves. Patterns are matched as
/// globs against **project-relative POSIX paths** (forward slashes), the same
/// keys analyzers already produce via `toPosixRelative`.
///
/// ## Configuration
/// An optional `.flutter_cleanup.yaml` in the project root may list extra
/// ignore patterns:
///
/// ```yaml
/// ignore:
///   - "lib/generated/**"
///   - "assets/legacy/**"
/// ```
///
/// A missing or empty file is a no-op — only [defaultIgnorePatterns] apply, with
/// no warning or error. Only the top-level `ignore:` key is read; any other
/// top-level keys are silently tolerated so the schema can grow later (e.g. a
/// future `duplicate_code:` section) without breaking this version.
///
/// ## Glob semantics
/// Backed by `package:glob`. `*` matches within a path segment; `**` matches
/// across segments. So `**/*.g.dart` matches `lib/a/foo.g.dart`, and
/// `lib/generated/**` matches everything under `lib/generated/` at any depth.
/// Globs are built with the POSIX [p.Context] so matching uses `/` on every
/// platform (without this the package would default to `\` on Windows and these
/// patterns would never match).
class IgnoreService {
  /// Builds a service from an explicit list of glob [patterns].
  ///
  /// Useful for tests and for callers that already have a resolved pattern list.
  /// Most callers use [IgnoreService.forProject] instead.
  IgnoreService(List<String> patterns)
      : _globs = [
          for (final pattern in patterns) Glob(pattern, context: p.posix),
        ];

  /// Loads ignore patterns for the project rooted at [root].
  ///
  /// Reads `<root>/.flutter_cleanup.yaml` if present and merges any user
  /// patterns on top of [defaultIgnorePatterns]. A missing/empty/invalid file
  /// yields the defaults only.
  factory IgnoreService.forProject(String root) {
    return IgnoreService([...defaultIgnorePatterns, ..._readUserPatterns(root)]);
  }

  /// Built-in patterns that are always ignored, even without a config file.
  /// User-defined patterns are added on top of these.
  ///
  /// These cover the code-generation outputs common across the Flutter
  /// ecosystem (almost always machine-written noise for duplicate/unused
  /// analysis) plus Flutter tooling artifacts:
  ///
  /// - `**/*.g.dart` — json_serializable, retrofit, hive, etc.
  /// - `**/*.freezed.dart` — freezed
  /// - `**/*.mocks.dart` — mockito
  /// - `**/*.gr.dart` — auto_route
  /// - `**/*.pb.dart`, `**/*.pbgrpc.dart`, `**/*.pbjson.dart`,
  ///   `**/*.pbenum.dart` — protobuf / gRPC (`protoc-gen-dart`). These are
  ///   emitted unconditionally (JSON/reflection descriptors, enum stubs) and are
  ///   routinely never imported, so they are noise rather than cleanup targets.
  /// - `.flutter-plugins`, `.flutter-plugins-dependencies` — Flutter tool output
  static const List<String> defaultIgnorePatterns = [
    '**/*.g.dart',
    '**/*.freezed.dart',
    '**/*.mocks.dart',
    '**/*.gr.dart',
    '**/*.pb.dart',
    '**/*.pbgrpc.dart',
    '**/*.pbjson.dart',
    '**/*.pbenum.dart',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
  ];

  /// The name of the optional project-root config file.
  static const String configFileName = '.flutter_cleanup.yaml';

  final List<Glob> _globs;

  /// Whether [projectRelativePath] should be excluded from analysis.
  ///
  /// [projectRelativePath] must be a project-relative POSIX path (forward
  /// slashes), as produced by `toPosixRelative`.
  bool isIgnored(String projectRelativePath) =>
      _globs.any((glob) => glob.matches(projectRelativePath));

  /// Reads the `ignore:` list from `<root>/.flutter_cleanup.yaml`.
  ///
  /// Returns an empty list when the file is absent, empty, not a map, or has no
  /// (or a non-list) `ignore:` key. Only `String` entries are kept.
  static List<String> _readUserPatterns(String root) {
    final file = File(p.join(root, configFileName));
    if (!file.existsSync()) return const [];

    final dynamic doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return const [];

    final dynamic ignore = doc['ignore'];
    if (ignore is! YamlList) return const [];

    return [
      for (final dynamic entry in ignore)
        if (entry is String) entry,
    ];
  }
}
