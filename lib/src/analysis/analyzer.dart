import '../models/project_paths.dart';
import 'analysis_result.dart';

/// The contract every analyzer implements.
///
/// This is the extension seam for the tool: future capabilities
/// (`unused-assets`, `unused-files`, `graph`, ...) implement [Analyzer] and
/// are wired into commands without changing the CLI core (Open/Closed
/// principle).
///
/// The interface is framework-agnostic — it depends only on resolved project
/// paths and emits [AnalysisResult]s, with no knowledge of how results are
/// presented or which command invoked it.
abstract interface class Analyzer {
  /// A short, unique name for this analyzer (used in output and selection).
  String get name;

  /// Runs the analysis against the project located at [paths].
  Future<AnalysisResult> analyze(ProjectPaths paths);
}
