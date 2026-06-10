import 'architecture_rule.dart';
import 'feature_rules.dart';
import 'layer_rules.dart';
import 'riverpod_rules.dart';
import 'routing_rules.dart';
import 'structure_rules.dart';

/// The Clean Architecture rule set (ARCH101–503).
///
/// A plain factory list for Phase 1–2: easy to read, test, and reorder. A
/// dynamic `RuleRegistry` is deferred to Phase 4, when alternate architecture
/// styles (DDD/MVC/Feature-Sliced) actually need pluggable registration.
List<ArchitectureRule> cleanArchitectureRules() => const [
      // ARCH1xx — layer dependency & purity
      DomainPurityRule(),
      LayerImportRule(),
      PresentationPurityRule(),
      // ARCH2xx — structure & element placement
      FeatureCompletenessRule(),
      ElementPlacementRule(),
      RepositoryContractRule(),
      // ARCH3xx — Riverpod
      RiverpodInjectionRule(),
      // ARCH4xx — routing
      RoutingRule(),
      // ARCH5xx — feature boundaries
      FeatureBoundaryRule(),
      CircularDependencyRule(),
    ];
