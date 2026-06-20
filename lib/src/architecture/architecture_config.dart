import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Project-specific extensions to the recognized architecture vocabulary.
///
/// The built-in [StructureVocabularyRule] vocabulary is intentionally strict so
/// stray folders can't silently escape the layer rules. Real projects, however,
/// legitimately grow folders the canonical layout doesn't name (`effects/`,
/// `adapters/`, …). Rather than fork the tool, a project may *extend* the
/// vocabulary through `.flutter_cleanup.yaml`:
///
/// ```yaml
/// architecture:
///   sublayers:
///     presentation: [effects]     # extra presentation/ sub-folders
///     data: [adapters]            # extra data/ sub-folders
///   top_level: [config]           # extra lib/<dir> folders
/// ```
///
/// Entries are **added** to the built-ins, never replace them. Parsing is
/// tolerant (mirrors [IgnoreService]): a missing file/section, wrong types, or
/// unknown keys yield [ArchitectureConfig.empty] with no error, so the schema
/// can keep growing without breaking older configs.
class ArchitectureConfig {
  const ArchitectureConfig({
    this.extraSublayers = const {},
    this.extraTopLevelDirs = const {},
  });

  /// A config that adds nothing — only the built-in vocabulary applies.
  static const ArchitectureConfig empty = ArchitectureConfig();

  /// Layer name (`data`/`domain`/`application`/`presentation`) → extra
  /// recognized sub-folder names beyond the built-in vocabulary.
  final Map<String, Set<String>> extraSublayers;

  /// Extra top-level folders under `lib/` to treat as recognized (beyond
  /// `core`/`features`/`shared`/`initialization`/`routing`).
  final Set<String> extraTopLevelDirs;

  /// The config-file key (shared with [IgnoreService]).
  static const String configFileName = '.flutter_cleanup.yaml';

  /// Loads the `architecture:` section from `<root>/.flutter_cleanup.yaml`.
  ///
  /// Returns [empty] when the file is absent, unreadable, not a map, or has no
  /// usable `architecture:` section.
  factory ArchitectureConfig.forProject(String root) {
    final file = File(p.join(root, configFileName));
    if (!file.existsSync()) return empty;

    final dynamic doc;
    try {
      doc = loadYaml(file.readAsStringSync());
    } catch (_) {
      return empty; // Malformed YAML — fall back to built-ins only.
    }
    if (doc is! YamlMap) return empty;

    final dynamic arch = doc['architecture'];
    if (arch is! YamlMap) return empty;

    return ArchitectureConfig(
      extraSublayers: _readSublayers(arch['sublayers']),
      extraTopLevelDirs: _readStringSet(arch['top_level']),
    );
  }

  /// Reads `sublayers:` as `{layer: [names…]}`, keeping only string entries.
  static Map<String, Set<String>> _readSublayers(dynamic node) {
    if (node is! YamlMap) return const {};
    final result = <String, Set<String>>{};
    node.forEach((dynamic layer, dynamic names) {
      if (layer is! String) return;
      final set = _readStringSet(names);
      if (set.isNotEmpty) result[layer] = set;
    });
    return result;
  }

  /// Reads a YAML list of strings into a set, ignoring non-string entries.
  static Set<String> _readStringSet(dynamic node) {
    if (node is! YamlList) return const {};
    return {
      for (final dynamic entry in node)
        if (entry is String) entry,
    };
  }
}
