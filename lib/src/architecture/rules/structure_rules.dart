import '../../models/finding.dart';
import '../architecture_config.dart';
import '../architecture_context.dart';
import '../architecture_violation.dart';
import '../definition/layer.dart';
import 'architecture_rule.dart';
import 'rule_helpers.dart';

/// ARCH201–203 — every feature must contain `data`, `domain`, and
/// `presentation` layer folders.
class FeatureCompletenessRule implements ArchitectureRule {
  const FeatureCompletenessRule();

  static const _codes = {
    Layer.data: ('ARCH201', 'data'),
    Layer.domain: ('ARCH202', 'domain'),
    Layer.presentation: ('ARCH203', 'presentation'),
  };

  @override
  String get name => 'feature-completeness';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final entry in context.featureLayerDirs.entries) {
      final feature = entry.key;
      final present = entry.value;
      final anchor = context.firstFileOf(feature);
      final filePath = anchor?.relPath ?? 'lib/features/$feature';

      for (final layer in const [Layer.data, Layer.domain, Layer.presentation]) {
        if (present.contains(layer)) continue;
        final (code, label) = _codes[layer]!;
        yield ArchitectureViolation(
          code: code,
          severity: Severity.warning,
          confidence: Confidence.high,
          filePath: filePath,
          line: anchor == null ? null : 1,
          featureName: feature,
          message: 'Feature "$feature" is missing its "$label" layer.',
        );
      }
    }
  }
}

/// ARCH204–208 — architectural elements must live in their designated folder.
///
/// Detection is naming-based (`*UseCase`, `*RepositoryImpl`, `*Model`, …), which
/// is the only signal available without type resolution; weakly-conventional
/// elements (entities) are graded [Confidence.medium] accordingly.
class ElementPlacementRule implements ArchitectureRule {
  const ElementPlacementRule();

  @override
  String get name => 'element-placement';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      for (final cls in classDeclarations(file.unit)) {
        final name = className(cls);
        final line = file.lineAt(cls.offset);

        ArchitectureViolation make(
          String code,
          String message, {
          Confidence confidence = Confidence.high,
        }) =>
            ArchitectureViolation(
              code: code,
              severity: Severity.warning,
              confidence: confidence,
              filePath: file.relPath,
              line: line,
              featureName: file.layer.feature,
              layer: file.layer.layer,
              message: message,
            );

        if ((name.endsWith('UseCase') || name.endsWith('Usecase')) &&
            !file.layer.isUseCase) {
          yield make('ARCH204',
              'Use case "$name" must live in domain/usecases.');
        } else if (name.endsWith('RepositoryImpl') &&
            !file.layer.isRepositoryImpl) {
          yield make('ARCH206',
              'Repository implementation "$name" must live in data/repositories.');
        } else if (isAbstractClass(cls) &&
            name.endsWith('Repository') &&
            !file.layer.isDomainContract) {
          yield make('ARCH205',
              'Repository contract "$name" must live in domain/repositories.');
        } else if (name.endsWith('Model') && !file.layer.isModel) {
          yield make('ARCH207', 'Model "$name" must live in data/models.');
        } else if (name.endsWith('Entity') && !file.layer.isEntity) {
          yield make('ARCH208', 'Entity "$name" must live in domain/entities.',
              confidence: Confidence.medium);
        }
      }
    }
  }
}

/// ARCH210–212 — strict folder vocabulary: every analyzed file must live in a
/// recognized location, so nothing silently escapes the layer rules.
///
/// Files in unrecognized folders are classified `Layer.unknown` and skipped by
/// the dependency/purity rules (ARCH1xx). Without this rule that is an
/// invisible blind spot; with it, every blind spot is reported:
///
/// - **ARCH210** — a folder directly under a feature that is not `data/`,
///   `domain/`, `application/`, or `presentation/` (e.g. `infrastructure/`,
///   `state/`), or a loose `.dart` file directly under the feature root.
/// - **ARCH211** — a sub-folder directly under a layer that is not in that
///   layer's vocabulary
///   (`data/{datasources,data_sources,models,mappers,dto,repositories}`,
///   `domain/{entities,repositories,usecases,value_objects,services}`,
///   `application/{services,coordinators,facades,runtime}`,
///   `presentation/{pages,providers,widgets,controllers,dialogs}`). Deeper
///   organizational folders
///   under a recognized sub-folder (e.g. `presentation/widgets/fields/`) are
///   allowed, as are loose files directly under a layer.
/// - **ARCH212** — a top-level folder under `lib/` other than `core/`,
///   `features/`, `shared/`, `initialization/`, or `routing/` (e.g.
///   `lib/utils/`). Loose files directly under `lib/` (`main.dart`, `app.dart`)
///   are allowed.
///
/// Each offending folder is reported once (anchored to its first file by path),
/// not once per file. Detection is derived from analyzed Dart file paths, so a
/// folder containing no Dart files is not reported — it also cannot affect the
/// architecture.
class StructureVocabularyRule implements ArchitectureRule {
  const StructureVocabularyRule();

  /// Top-level folders under `lib/` that are part of the architecture.
  /// `core`/`shared`/`initialization`/`routing` are shared infrastructure;
  /// `features` holds the feature layers.
  static const _topLevelDirs = {
    'core',
    'features',
    'shared',
    'initialization',
    'routing',
  };

  static const _layerDirs = {'data', 'domain', 'application', 'presentation'};

  static const _sublayerDirsByLayer = {
    'data': {
      'datasources',
      'data_sources',
      'models',
      'mappers',
      'dto',
      'repositories',
    },
    'domain': {'entities', 'repositories', 'usecases', 'value_objects', 'services'},
    'application': {'services', 'coordinators', 'facades', 'runtime'},
    'presentation': {
      'pages',
      'providers',
      'widgets',
      'controllers',
      'dialogs',
      'painters',
      'styles',
    },
  };

  /// Merges the built-in [_sublayerDirsByLayer] with any project extras declared
  /// under `architecture.sublayers` in `.flutter_cleanup.yaml`. Extras are
  /// additive — they widen a layer's vocabulary, never narrow it.
  static Map<String, Set<String>> _mergedSublayers(ArchitectureConfig config) {
    if (config.extraSublayers.isEmpty) return _sublayerDirsByLayer;
    return {
      for (final entry in _sublayerDirsByLayer.entries)
        entry.key: {...entry.value, ...?config.extraSublayers[entry.key]},
    };
  }

  /// Reverse of a sub-layer map: sub-folder name → the layer whose vocabulary
  /// owns it. Used to explain *why* a sub-folder is misplaced when its name is
  /// valid but used in the wrong layer (e.g. `domain/models`). A name shared by
  /// two layers (`repositories`/`services`) is never unrecognized in either, so
  /// it never reaches the misplacement check and the arbitrary winner is moot.
  static Map<String, String> _ownerLayerByDir(
    Map<String, Set<String>> sublayers,
  ) =>
      {
        for (final entry in sublayers.entries)
          for (final dir in entry.value) dir: entry.key,
      };

  /// A trailing clause explaining that [subName] is recognized vocabulary, just
  /// from another layer — so naming a [layerDir] sub-folder after it is
  /// misleading. Empty for genuine synonyms (`screens`, `state`) that don't
  /// belong to any layer.
  static String _misplacedVocabularyNote(
    Map<String, String> ownerByDir,
    String layerDir,
    String subName,
  ) {
    final owner = ownerByDir[subName];
    if (owner == null || owner == layerDir) return '';
    if (layerDir == 'domain' && subName == 'models') {
      return ' "models" is the data layer\'s vocabulary, so "domain/models" is '
          'misleading: if these are pure domain types rename the folder to '
          'entities/, and keep serializable DTOs in data/models/.';
    }
    return ' "$subName" is the $owner layer\'s vocabulary, so a $layerDir '
        'sub-folder named "$subName" is misleading.';
  }

  @override
  String get name => 'structure-vocabulary';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    // Built-in vocabulary widened by any project extras from .flutter_cleanup.yaml.
    final sublayerDirsByLayer = _mergedSublayers(context.config);
    final ownerLayerByDir = _ownerLayerByDir(sublayerDirsByLayer);
    final topLevelDirs = {..._topLevelDirs, ...context.config.extraTopLevelDirs};

    // folder path → first (lowest-sorted) file inside it, for stable anchors.
    final unknownTopLevel = <String, String>{};
    final unknownLayerDirs = <String, (String, String)>{}; // path → (feature, anchor)
    final unknownSublayers = <String, (String, Layer, String)>{};
    final looseFeatureFiles = <(String, String)>[];

    void record(Map<String, String> map, String folder, String file) {
      final current = map[folder];
      if (current == null || file.compareTo(current) < 0) map[folder] = file;
    }

    for (final file in context.files) {
      final segments = file.relPath.split('/');
      if (segments.length < 2 || segments.first != 'lib') continue;

      // ARCH212 — lib/<dir>/** where <dir> is not a recognized top-level folder.
      if (segments.length >= 3 && !topLevelDirs.contains(segments[1])) {
        record(unknownTopLevel, 'lib/${segments[1]}', file.relPath);
        continue;
      }
      if (segments[1] != 'features') continue;

      // ARCH210 — loose file directly under the feature root.
      if (segments.length == 4) {
        looseFeatureFiles.add((segments[2], file.relPath));
        continue;
      }
      if (segments.length < 5) continue;

      final feature = segments[2];
      final layerDir = segments[3];

      // ARCH210 — unrecognized layer folder under a feature.
      if (!_layerDirs.contains(layerDir)) {
        final folder = 'lib/features/$feature/$layerDir';
        final current = unknownLayerDirs[folder];
        if (current == null || file.relPath.compareTo(current.$2) < 0) {
          unknownLayerDirs[folder] = (feature, file.relPath);
        }
        continue;
      }

      // ARCH211 — unrecognized sub-folder directly under a layer.
      if (segments.length >= 6 &&
          !sublayerDirsByLayer[layerDir]!.contains(segments[4])) {
        final folder = 'lib/features/$feature/$layerDir/${segments[4]}';
        final current = unknownSublayers[folder];
        if (current == null || file.relPath.compareTo(current.$3) < 0) {
          unknownSublayers[folder] =
              (feature, file.layer.layer, file.relPath);
        }
      }
    }

    for (final folder in unknownLayerDirs.keys.toList()..sort()) {
      final (feature, anchor) = unknownLayerDirs[folder]!;
      yield ArchitectureViolation(
        code: 'ARCH210',
        severity: Severity.warning,
        confidence: Confidence.high,
        filePath: anchor,
        line: 1,
        featureName: feature,
        relatedFiles: [folder],
        message: 'Unrecognized folder "$folder" — feature folders must be '
            'data/, domain/, or presentation/. Files in it are not checked by '
            'the layer rules.',
      );
    }

    for (final (feature, file) in looseFeatureFiles..sort((a, b) => a.$2.compareTo(b.$2))) {
      yield ArchitectureViolation(
        code: 'ARCH210',
        severity: Severity.warning,
        confidence: Confidence.high,
        filePath: file,
        line: 1,
        featureName: feature,
        message: 'File is outside any layer folder — feature files must live '
            'under data/, domain/, or presentation/.',
      );
    }

    for (final folder in unknownSublayers.keys.toList()..sort()) {
      final (feature, layer, anchor) = unknownSublayers[folder]!;
      final layerDir = folder.split('/')[3];
      final subName = folder.split('/').last;
      final allowed =
          (sublayerDirsByLayer[layerDir]!.toList()..sort()).join('/, ');
      yield ArchitectureViolation(
        code: 'ARCH211',
        severity: Severity.warning,
        confidence: Confidence.high,
        filePath: anchor,
        line: 1,
        featureName: feature,
        layer: layer,
        relatedFiles: [folder],
        message: 'Unrecognized $layerDir sub-folder "$folder" — allowed: '
            '$allowed/.'
            '${_misplacedVocabularyNote(ownerLayerByDir, layerDir, subName)}',
      );
    }

    for (final folder in unknownTopLevel.keys.toList()..sort()) {
      yield ArchitectureViolation(
        code: 'ARCH212',
        severity: Severity.warning,
        confidence: Confidence.high,
        filePath: unknownTopLevel[folder]!,
        line: 1,
        relatedFiles: [folder],
        message: 'Folder "$folder" is outside the architecture — top-level '
            'folders must be lib/core/, lib/features/, lib/shared/, '
            'lib/initialization/, or lib/routing/. Files in it are not checked '
            'by the layer rules.',
      );
    }
  }
}

/// ARCH209 — a repository implementation must implement a domain repository
/// contract (`implements …Repository`).
///
/// Always [Confidence.medium]: without element resolution, typedef aliases
/// (`typedef Repo = UserRepository`) and generic bases
/// (`implements BaseRepository<T>`) can't be proven, so this rule never claims
/// certainty.
class RepositoryContractRule implements ArchitectureRule {
  const RepositoryContractRule();

  @override
  String get name => 'repository-contract';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      for (final cls in classDeclarations(file.unit)) {
        final name = className(cls);
        if (!name.endsWith('RepositoryImpl')) continue;

        final interfaces = implementsNames(cls);
        final hasContract = interfaces.any((i) => i.endsWith('Repository'));
        if (hasContract) continue;

        yield ArchitectureViolation(
          code: 'ARCH209',
          severity: Severity.warning,
          confidence: Confidence.medium,
          filePath: file.relPath,
          line: file.lineAt(cls.offset),
          featureName: file.layer.feature,
          layer: file.layer.layer,
          message: 'Repository implementation "$name" must implement a domain '
              'repository contract.',
        );
      }
    }
  }
}
