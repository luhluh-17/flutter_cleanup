import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analysis/path_utils.dart';
import '../models/project_paths.dart';
import '../services/ignore_service.dart';
import 'dart_file_info.dart';
import 'definition/architecture_definition.dart';
import 'definition/layer.dart';
import 'dependency_graph.dart';
import 'import_resolver.dart';

/// The shared, parse-once model every architecture rule reads.
///
/// Walks `lib/` (honoring `.flutter_cleanup.yaml` ignores), parses each Dart
/// file exactly once, classifies it, resolves its imports, and assembles the
/// [DartFileInfo] list plus the [DependencyGraph] and per-feature layer presence.
/// Rules receive this context and never touch the filesystem themselves.
class ArchitectureContext {
  ArchitectureContext({
    required this.root,
    required this.definition,
    required this.files,
    required this.graph,
    required this.featureLayerDirs,
  });

  /// Absolute project root.
  final String root;

  /// The active architecture style.
  final ArchitectureDefinition definition;

  /// Every parsed Dart file under `lib/`.
  final List<DartFileInfo> files;

  /// The internal import dependency graph (file- and feature-level).
  final DependencyGraph graph;

  /// feature → the set of layer folders (`data`/`domain`/`presentation`) that
  /// physically exist for that feature. Drives the completeness rules (ARCH201–
  /// 203), which must see a *missing* folder even when no file references it.
  final Map<String, Set<Layer>> featureLayerDirs;

  /// All discovered feature names.
  Set<String> get featureNames => featureLayerDirs.keys.toSet();

  /// Returns the first file belonging to [feature], or null. Used to anchor
  /// feature-level diagnostics (cycles, missing layers) to a real file.
  DartFileInfo? firstFileOf(String feature) {
    for (final f in files) {
      if (f.layer.feature == feature) return f;
    }
    return null;
  }

  /// Builds the context for the project at [paths].
  ///
  /// [definition] defaults to [CleanArchitectureDefinition]. Files that fail to
  /// parse are skipped rather than aborting the run (same tolerance as the other
  /// AST analyzers).
  factory ArchitectureContext.build(
    ProjectPaths paths, {
    ArchitectureDefinition definition = const CleanArchitectureDefinition(),
  }) {
    final packageName = _readPackageName(paths.pubspec) ?? 'app';
    final ignore = IgnoreService.forProject(paths.root);
    final resolver =
        ImportResolver(packageName: packageName, definition: definition);

    final files = <DartFileInfo>[];
    final libDir = Directory(paths.libDir);
    if (libDir.existsSync()) {
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || p.extension(entity.path) != '.dart') continue;
        final relPath = toPosixRelative(paths.root, entity.path);
        if (ignore.isIgnored(relPath)) continue;

        final String source;
        try {
          source = entity.readAsStringSync();
        } on FileSystemException {
          continue;
        }

        try {
          final parsed = parseString(content: source, throwIfDiagnostics: false);
          final layer = definition.classify(relPath);
          files.add(DartFileInfo(
            relPath: relPath,
            layer: layer,
            unit: parsed.unit,
            lineInfo: parsed.lineInfo,
            imports:
                resolver.resolve(parsed.unit, relPath, parsed.lineInfo),
          ));
        } catch (_) {
          // Unparseable file — skip rather than abort the whole run.
          continue;
        }
      }
    }

    return ArchitectureContext(
      root: paths.root,
      definition: definition,
      files: files,
      graph: DependencyGraph.build(files),
      featureLayerDirs: _scanFeatureLayerDirs(paths.libDir),
    );
  }

  /// Reads the `name:` field from `pubspec.yaml`, used to recognize
  /// `package:<self>/…` imports as internal. Null when unreadable.
  static String? _readPackageName(String pubspecPath) {
    final file = File(pubspecPath);
    if (!file.existsSync()) return null;
    try {
      final dynamic doc = loadYaml(file.readAsStringSync());
      if (doc is YamlMap && doc['name'] is String) return doc['name'] as String;
    } catch (_) {
      // Malformed pubspec — fall back to the default package name.
    }
    return null;
  }

  /// Records which of `data`/`domain`/`presentation` exist on disk per feature.
  static Map<String, Set<Layer>> _scanFeatureLayerDirs(String libDir) {
    const layerByDir = {
      'data': Layer.data,
      'domain': Layer.domain,
      'presentation': Layer.presentation,
    };
    final result = <String, Set<Layer>>{};
    final featuresDir = Directory(p.join(libDir, 'features'));
    if (!featuresDir.existsSync()) return result;

    for (final entity in featuresDir.listSync()) {
      if (entity is! Directory) continue;
      final feature = p.basename(entity.path);
      final present = <Layer>{};
      for (final entry in layerByDir.entries) {
        if (Directory(p.join(entity.path, entry.key)).existsSync()) {
          present.add(entry.value);
        }
      }
      result[feature] = present;
    }
    return result;
  }
}
