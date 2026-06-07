import '../models/project_paths.dart';

/// A single finding produced by an [Analyzer].
class Finding {
  const Finding({required this.message, this.path});

  /// A human-readable description of the finding.
  final String message;

  /// The file or directory the finding relates to, if any.
  final String? path;
}

/// The result of running an [Analyzer] against a project.
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
}

/// The contract every analyzer implements.
///
/// This is the extension seam for the tool: future capabilities (unused
/// assets, dead code, dependency relationships) implement [Analyzer] and are
/// wired into commands without changing the CLI core (Open/Closed principle).
abstract interface class Analyzer {
  /// A short, unique name for this analyzer (used in output and selection).
  String get name;

  /// Runs the analysis against the project located at [paths].
  Future<AnalysisResult> analyze(ProjectPaths paths);
}
