import '../architecture_context.dart';
import '../architecture_violation.dart';

/// One cohesive architecture concern that inspects the [ArchitectureContext] and
/// emits zero or more [ArchitectureViolation]s.
///
/// A rule may emit violations under several ARCH codes when they form one
/// concern (e.g. the layer-import rule chooses the most specific of 102–106 per
/// import). For Phase 1–2 the rule set is assembled by the plain factory
/// `cleanArchitectureRules()`; a dynamic registry is deferred to Phase 4, when
/// multiple architecture styles actually need it.
abstract interface class ArchitectureRule {
  /// A short identifier for the rule, used in debugging/diagnostics.
  String get name;

  /// Inspects [context] and yields any violations found.
  Iterable<ArchitectureViolation> check(ArchitectureContext context);
}
