import '../../models/finding.dart';
import '../architecture_context.dart';
import '../architecture_violation.dart';
import '../ast/ast_scanner.dart';
import '../definition/layer.dart';
import 'architecture_rule.dart';
import 'rule_helpers.dart';

/// ARCH301 — a Riverpod notifier must receive its dependencies through providers
/// (`ref.read(...)`), not construct them itself.
///
/// Heuristic and confidence-graded: a literal `UserRepositoryImpl()` /
/// `UserRemoteDataSource()` inside a `*Notifier` is [Confidence.high]; a plain
/// `*Repository()` is [Confidence.medium]. Indirect factory calls
/// (`final repo = createRepo();`) are intentionally *not* flagged — they can't be
/// proven dependency construction without type resolution.
class RiverpodInjectionRule implements ArchitectureRule {
  const RiverpodInjectionRule();

  @override
  String get name => 'riverpod-injection';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      if (file.layer.layer != Layer.presentation) continue;

      for (final cls in classDeclarations(file.unit)) {
        final name = className(cls);
        final superName = superclassName(cls) ?? '';
        final isNotifier =
            name.endsWith('Notifier') || superName.endsWith('Notifier');
        if (!isNotifier) continue;

        for (final instantiation in findInstantiations(cls)) {
          final type = instantiation.typeName;
          if (!isRepositoryType(type) && !isDatasourceType(type)) continue;

          final confidence =
              isRepositoryImplType(type) || isDatasourceType(type)
                  ? Confidence.high
                  : Confidence.medium;

          yield ArchitectureViolation(
            code: 'ARCH301',
            severity: Severity.warning,
            confidence: confidence,
            filePath: file.relPath,
            line: file.lineAt(instantiation.offset),
            featureName: file.layer.feature,
            layer: Layer.presentation,
            message: 'Notifier "$name" constructs its own dependency ($type). '
                'Inject it through a Riverpod provider instead.',
          );
        }
      }
    }
  }
}
