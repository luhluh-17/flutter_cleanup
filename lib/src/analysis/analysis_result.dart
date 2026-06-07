import '../models/finding.dart';

/// The result of running an analyzer against a project.
///
/// Wraps the [Finding]s an analyzer produced together with the name of the
/// analyzer that produced them, so callers can aggregate and render results
/// from several analyzers uniformly.
class AnalysisResult {
  const AnalysisResult({required this.analyzerName, required this.findings});

  /// Convenience for an analyzer that found nothing.
  const AnalysisResult.empty(String analyzerName)
      : this(analyzerName: analyzerName, findings: const []);

  /// The name of the analyzer that produced this result.
  final String analyzerName;

  /// The findings discovered during analysis.
  final List<Finding> findings;

  /// Whether the analyzer produced any findings.
  bool get hasFindings => findings.isNotEmpty;

  /// Serializes this result to a JSON-encodable map.
  ///
  /// The analyzer name is exposed under the `analyzer` key. Document-level
  /// metadata such as `schemaVersion` is added by the renderer, not here, so
  /// results nested in an aggregate document do not repeat it.
  Map<String, dynamic> toJson() => {
        'analyzer': analyzerName,
        'findings': [for (final f in findings) f.toJson()],
      };
}
