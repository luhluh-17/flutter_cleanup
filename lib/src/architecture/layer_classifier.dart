import 'definition/layer.dart';
import 'definition/layer_info.dart';

/// Classifies a project-relative POSIX path into a [LayerInfo] for the
/// Clean Architecture + Feature-Based layout.
///
/// This is the single source of truth for "which layer is this file?". It is
/// pure (path in, [LayerInfo] out), with no I/O, so it is trivially unit-testable
/// and reusable by both the [ArchitectureDefinition] and the import resolver.
///
/// Recognized shapes (paths are forward-slashed, as produced by
/// `toPosixRelative`):
/// - `lib/core/**` → [Layer.core]; `lib/core/config/router/**` also flags
///   [LayerInfo.isRouterDir].
/// - `lib/features/<feature>/<layer>/<sublayer>/**` → the feature layer/sublayer.
/// - anything else under `lib/` (e.g. `lib/main.dart`) → [LayerInfo.unknown].
class LayerClassifier {
  const LayerClassifier();

  static const _layerByDir = {
    'data': Layer.data,
    'domain': Layer.domain,
    'presentation': Layer.presentation,
  };

  static const _sublayerByDir = {
    'datasources': Sublayer.datasources,
    'models': Sublayer.models,
    'repositories': Sublayer.repositories,
    'entities': Sublayer.entities,
    'usecases': Sublayer.usecases,
    'providers': Sublayer.providers,
    'pages': Sublayer.pages,
    'widgets': Sublayer.widgets,
  };

  /// Classifies [relPath] (a project-relative, forward-slashed path).
  LayerInfo classify(String relPath) {
    final segments = relPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty || segments.first != 'lib') return LayerInfo.unknown;

    // lib/core/**
    if (segments.length >= 2 && segments[1] == 'core') {
      final isRouter = segments.length >= 4 &&
          segments[2] == 'config' &&
          segments[3] == 'router';
      return LayerInfo(
        layer: Layer.core,
        sublayer: Sublayer.none,
        isCore: true,
        isRouterDir: isRouter,
      );
    }

    // lib/features/<feature>/<layer>/<sublayer>/**
    if (segments.length >= 3 && segments[1] == 'features') {
      final feature = segments[2];
      final layer = segments.length >= 4 ? _layerByDir[segments[3]] : null;
      if (layer == null) {
        // Under a feature, but not in a recognized layer dir.
        return LayerInfo(
          layer: Layer.unknown,
          sublayer: Sublayer.none,
          feature: feature,
        );
      }
      final sublayer = segments.length >= 5
          ? (_sublayerByDir[segments[4]] ?? Sublayer.none)
          : Sublayer.none;
      return LayerInfo(layer: layer, sublayer: sublayer, feature: feature);
    }

    return LayerInfo.unknown;
  }
}
