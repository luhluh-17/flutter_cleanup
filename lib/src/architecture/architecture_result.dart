import '../analysis/analysis_result.dart';
import '../models/finding.dart';
import 'architecture_violation.dart';
import 'dependency_report.dart';

/// The architecture analyzer's result: the standard [AnalysisResult] findings
/// plus an architecture [score], per-code and per-category tallies, the rich
/// [violations], and the feature [dependencies] used by the report.
///
/// Extends [AnalysisResult] so it flows through the existing `all`/JSON pipeline
/// unchanged; the extra keys appear only on this analyzer's document.
class ArchitectureResult extends AnalysisResult {
  ArchitectureResult({
    required super.analyzerName,
    required this.violations,
    required this.score,
    required this.violationsByCode,
    required this.summary,
    required this.dependencies,
  }) : super(findings: [for (final v in violations) v.toFinding()]);

  /// The rich internal violations (superset of [findings]).
  final List<ArchitectureViolation> violations;

  /// 0–100 architecture score (100 = no violations).
  final int score;

  /// `{ARCH code: count}`, ordered by code.
  final Map<String, int> violationsByCode;

  /// `{category: count}` for all five categories.
  final Map<String, int> summary;

  /// `feature → sorted list of features it depends on`.
  final Map<String, List<String>> dependencies;

  /// The kind of analysis performed, surfaced so consumers know its limits.
  static const String analysisMode = 'syntactic-ast';

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'analysisMode': analysisMode,
        'score': score,
        'summary': summary,
        'violationsByCode': violationsByCode,
        'dependencies': dependencies,
      };

  /// Severity counts across [findings], for the text summary line.
  ({int errors, int warnings, int infos}) get severityCounts {
    var errors = 0, warnings = 0, infos = 0;
    for (final f in findings) {
      switch (f.severity) {
        case Severity.error:
          errors++;
        case Severity.warning:
          warnings++;
        case Severity.info:
          infos++;
      }
    }
    return (errors: errors, warnings: warnings, infos: infos);
  }

  /// Renders the feature-dependency tree (ARCH `--report`).
  String renderDependencyReport() => renderDependencyTree(dependencies);
}
