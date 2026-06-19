import '../../models/finding.dart';
import '../architecture_context.dart';
import '../architecture_violation.dart';
import '../ast/ast_scanner.dart';
import '../dart_file_info.dart';
import '../definition/layer.dart';
import '../definition/layer_info.dart';
import 'architecture_rule.dart';
import 'rule_helpers.dart';

/// ARCH101 — the domain layer must not import infrastructure packages
/// (Flutter, Dio, Retrofit, Firebase, Hive, Drift, SharedPreferences).
class DomainPurityRule implements ArchitectureRule {
  const DomainPurityRule();

  @override
  String get name => 'domain-purity';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      if (file.layer.layer != Layer.domain) continue;
      for (final import in file.imports) {
        final pkg = import.packageName;
        if (pkg == null || import.isInternal) continue;
        if (context.definition.isForbiddenInDomain(pkg)) {
          yield ArchitectureViolation(
            code: 'ARCH101',
            severity: Severity.error,
            confidence: Confidence.high,
            filePath: file.relPath,
            line: import.line,
            featureName: file.layer.feature,
            layer: Layer.domain,
            message: 'Domain layer must not import "$pkg".',
          );
        }
      }
    }
  }
}

/// ARCH102–106 — illegal *internal* import directions between layers.
///
/// One rule chooses the most specific code per offending import, so each bad
/// import is reported once: presentation→datasource (103), presentation→repo
/// impl (104), presentation→other-disallowed (105), entity→model (102), and any
/// remaining direction violation against the matrix (106).
class LayerImportRule implements ArchitectureRule {
  const LayerImportRule();

  @override
  String get name => 'layer-imports';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      for (final import in file.imports) {
        if (!import.isInternal) continue;
        final target = import.targetLayer;
        if (target == null) continue;

        final violation = _classify(file, import.line, target);
        if (violation != null) yield violation;
      }
    }
  }

  ArchitectureViolation? _classify(
    DartFileInfo file,
    int line,
    LayerInfo tgt,
  ) {
    final src = file.layer;

    ArchitectureViolation make(
      String code,
      Severity severity,
      String message, {
      Confidence confidence = Confidence.high,
    }) =>
        ArchitectureViolation(
          code: code,
          severity: severity,
          confidence: confidence,
          filePath: file.relPath,
          line: line,
          featureName: src.feature,
          layer: src.layer,
          relatedFiles: [layerLabel(tgt)],
          message: message,
        );

    switch (src.layer) {
      case Layer.presentation:
        if (tgt.isDatasource) {
          return make('ARCH103', Severity.warning,
              'Presentation layer must not import datasources.');
        }
        if (tgt.isRepositoryImpl) {
          return make('ARCH104', Severity.warning,
              'Presentation layer must not import repository implementations.');
        }
        final allowed = tgt.isCore ||
            tgt.layer == Layer.presentation ||
            tgt.isUseCase ||
            tgt.isEntity;
        if (!allowed && tgt.layer.isFeatureLayer) {
          return make(
              'ARCH105',
              Severity.warning,
              'Presentation may only access use cases, entities, and providers '
              '(imported ${layerLabel(tgt)}).');
        }
        return null;
      case Layer.domain:
        if (tgt.layer == Layer.data) {
          if (src.isEntity && tgt.isModel) {
            return make('ARCH102', Severity.error,
                'Entities must not import models.');
          }
          return make('ARCH106', Severity.error,
              'Illegal layer dependency: domain must not import data.');
        }
        if (tgt.layer == Layer.presentation) {
          return make('ARCH106', Severity.error,
              'Illegal layer dependency: domain must not import presentation.');
        }
        return null;
      case Layer.data:
        if (tgt.layer == Layer.presentation) {
          return make('ARCH106', Severity.error,
              'Illegal layer dependency: data must not import presentation.');
        }
        return null;
      case Layer.core:
      case Layer.unknown:
        return null;
    }
  }
}

/// ARCH107–110 — presentation-layer purity, checked against the AST:
/// no `Dio()` (107), no data-source instantiation (108), no JSON serialization
/// (109), and pages must not directly instantiate repositories (110).
class PresentationPurityRule implements ArchitectureRule {
  const PresentationPurityRule();

  @override
  String get name => 'presentation-purity';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      if (file.layer.layer != Layer.presentation) continue;

      for (final instantiation in findInstantiations(file.unit)) {
        final type = instantiation.typeName;
        final line = file.lineAt(instantiation.offset);

        if (type == 'Dio') {
          yield _make(file, 'ARCH107', line, Confidence.high,
              'Presentation layer must not instantiate Dio.');
        } else if (isDatasourceType(type)) {
          yield _make(file, 'ARCH108', line, Confidence.high,
              'Presentation layer must not instantiate data sources ($type).');
        } else if (file.layer.isPage && isRepositoryType(type)) {
          final confidence = isRepositoryImplType(type)
              ? Confidence.high
              : Confidence.medium;
          yield _make(
              file,
              'ARCH110',
              line,
              confidence,
              'Pages must not directly instantiate repositories ($type). '
              'Obtain it from a Riverpod provider, e.g. ref.read(...).');
        }
      }

      for (final usage in findJsonSerialization(file.unit)) {
        // Declaring a serializable model in the UI is unambiguous; a
        // serialization *call* (`model.toJson()`) is not — a raw-JSON editor
        // looks identical to a serialize-at-the-boundary leak — so it is graded
        // medium.
        final confidence =
            usage.isDeclaration ? Confidence.high : Confidence.medium;
        yield _make(file, 'ARCH109', file.lineAt(usage.offset), confidence,
            'Presentation layer must not contain JSON serialization code.');
      }
    }
  }

  ArchitectureViolation _make(
    DartFileInfo file,
    String code,
    int line,
    Confidence confidence,
    String message,
  ) =>
      ArchitectureViolation(
        code: code,
        severity: Severity.warning,
        confidence: confidence,
        filePath: file.relPath,
        line: line,
        featureName: file.layer.feature,
        layer: Layer.presentation,
        message: message,
      );
}
