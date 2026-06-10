import '../analysis/analyzer.dart';
import '../models/project_paths.dart';
import 'architecture_context.dart';
import 'architecture_result.dart';
import 'architecture_violation.dart';
import 'definition/architecture_definition.dart';
import 'rules/architecture_rule.dart';
import 'rules/clean_architecture_rules.dart';

/// Detects Clean Architecture + Feature-Based + Riverpod violations
/// (ARCH101–503) across a project's `lib/` tree.
///
/// Builds the parse-once [ArchitectureContext], runs every rule, then projects
/// the rich [ArchitectureViolation]s onto an [ArchitectureResult] (findings +
/// score + summary + dependency map). The analysis is *syntactic* (no element
/// resolution), so some rules are confidence-graded.
class ArchitectureAnalyzer implements Analyzer {
  ArchitectureAnalyzer({
    ArchitectureDefinition definition = const CleanArchitectureDefinition(),
    List<ArchitectureRule>? rules,
  })  :
        // ignore: prefer_initializing_formals — named params can't be private
        _definition = definition,
        _rules = rules ?? cleanArchitectureRules();

  final ArchitectureDefinition _definition;
  final List<ArchitectureRule> _rules;

  @override
  String get name => 'architecture';

  @override
  Future<ArchitectureResult> analyze(ProjectPaths paths) async {
    final context =
        ArchitectureContext.build(paths, definition: _definition);

    final violations = <ArchitectureViolation>[
      for (final rule in _rules) ...rule.check(context),
    ]..sort(_byLocation);

    return ArchitectureResult(
      analyzerName: name,
      violations: violations,
      score: _score(violations),
      violationsByCode: _violationsByCode(violations),
      summary: _summary(violations),
      dependencies: _dependencies(context),
    );
  }

  /// Deterministic ordering: path, then line, then code.
  static int _byLocation(ArchitectureViolation a, ArchitectureViolation b) {
    final byPath = a.filePath.compareTo(b.filePath);
    if (byPath != 0) return byPath;
    final byLine = (a.line ?? 0).compareTo(b.line ?? 0);
    if (byLine != 0) return byLine;
    return a.code.compareTo(b.code);
  }

  /// Category-weighted score: start at 100, subtract each violation's category
  /// weight (feature cycles cost more than misplaced files), floor at 0.
  static int _score(List<ArchitectureViolation> violations) {
    var penalty = 0;
    for (final v in violations) {
      penalty += v.category.weight;
    }
    final score = 100 - penalty;
    return score < 0 ? 0 : score;
  }

  static Map<String, int> _violationsByCode(
      List<ArchitectureViolation> violations) {
    final counts = <String, int>{};
    for (final v in violations) {
      counts[v.code] = (counts[v.code] ?? 0) + 1;
    }
    return {
      for (final code in counts.keys.toList()..sort()) code: counts[code]!,
    };
  }

  static Map<String, int> _summary(List<ArchitectureViolation> violations) {
    final summary = <String, int>{
      'layer': 0,
      'structure': 0,
      'riverpod': 0,
      'routing': 0,
      'feature': 0,
    };
    for (final v in violations) {
      summary[v.category.key] = (summary[v.category.key] ?? 0) + 1;
    }
    return summary;
  }

  static Map<String, List<String>> _dependencies(ArchitectureContext context) {
    final deps = <String, List<String>>{};
    for (final feature in context.featureNames) {
      final imports = context.graph.featureImports[feature] ?? const {};
      deps[feature] = imports.toList()..sort();
    }
    return deps;
  }
}
