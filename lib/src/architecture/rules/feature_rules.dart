import '../../models/finding.dart';
import '../architecture_context.dart';
import '../architecture_violation.dart';
import 'architecture_rule.dart';
import 'rule_helpers.dart';

/// ARCH501 & ARCH503 — feature-boundary hygiene.
///
/// - 501: a feature imports another feature, except via that feature's domain
///   *contracts* (`domain/repositories`) or shared `core/*`.
/// - 503: a feature depends on too many other features (god-feature fan-out).
class FeatureBoundaryRule implements ArchitectureRule {
  const FeatureBoundaryRule({this.maxFanOut = 5});

  /// Maximum number of other features a feature may depend on before ARCH503
  /// fires. A constant for now; config-ready for Phase 4.
  final int maxFanOut;

  @override
  String get name => 'feature-boundary';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    // ARCH501 — cross-feature imports (per offending import).
    for (final file in context.files) {
      final from = file.layer.feature;
      if (from == null) continue;

      for (final import in file.imports) {
        if (!import.isInternal) continue;
        final target = import.targetLayer;
        final to = target?.feature;
        if (to == null || to == from) continue;
        // A target outside the feature layers (an unrecognized/misplaced folder
        // or a loose file) is already reported by the structure rules. Counting
        // it as a cross-feature dependency would double-flag it and, for a
        // misplaced file inside a feature group, would misread an intra-group
        // import as crossing a boundary.
        if (!target!.layer.isFeatureLayer) continue;
        if (target.isDomainContract) continue; // shareable contract

        yield ArchitectureViolation(
          code: 'ARCH501',
          severity: Severity.warning,
          confidence: Confidence.high,
          filePath: file.relPath,
          line: import.line,
          featureName: from,
          relatedFiles: [import.targetRelPath ?? to],
          message: 'Cross-feature import: "$from" must not import "$to" '
              '(${layerLabel(target)}). Only core/* and domain contracts are '
              'allowed across features.',
        );
      }
    }

    // ARCH503 — fan-out.
    for (final feature in context.featureNames) {
      final dependsOn = context.graph.featureImports[feature] ?? const {};
      if (dependsOn.length <= maxFanOut) continue;
      final anchor = context.firstFileOf(feature);
      final sorted = dependsOn.toList()..sort();
      yield ArchitectureViolation(
        code: 'ARCH503',
        severity: Severity.warning,
        confidence: Confidence.high,
        filePath: anchor?.relPath ?? 'lib/features/$feature',
        line: anchor == null ? null : 1,
        featureName: feature,
        dependencyPath: sorted,
        message: 'Feature "$feature" depends on ${dependsOn.length} other '
            'features (max $maxFanOut): ${sorted.join(', ')}. Consider '
            'splitting it or extracting shared code into core/.',
      );
    }
  }
}

/// ARCH502 — circular dependencies between features.
class CircularDependencyRule implements ArchitectureRule {
  const CircularDependencyRule();

  @override
  String get name => 'circular-dependency';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final cycle in context.graph.featureCycles()) {
      final anchorFeature = cycle.first;
      final anchor = context.firstFileOf(anchorFeature);
      yield ArchitectureViolation(
        code: 'ARCH502',
        severity: Severity.error,
        confidence: Confidence.high,
        filePath: anchor?.relPath ?? 'lib/features/$anchorFeature',
        line: anchor == null ? null : 1,
        featureName: anchorFeature,
        cyclePath: cycle,
        message: 'Circular feature dependency: ${cycle.join(' → ')}.',
      );
    }
  }
}
