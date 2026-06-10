import '../../models/finding.dart';
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
