import '../analysis/analyzer.dart';
import '../analyzers/primary_constructors/primary_constructors_analyzer.dart';
import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports classes under `lib/` that are safe candidates for migration to a
/// Dart 3.12+ primary constructor.
///
/// Validates the project, then runs the [PrimaryConstructorsAnalyzer] and
/// renders its findings via [ReportPrinter]. The command does no analysis itself
/// and the analyzer does no printing — each layer has a single responsibility.
class PrimaryConstructorsCommand extends FlutterCleanupCommand {
  PrimaryConstructorsCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? const PrimaryConstructorsAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _analyzer;

  @override
  String get name => 'primary-constructors';

  @override
  String get description =>
      'Find classes that are safe to migrate to a Dart 3.12+ primary '
      'constructor under lib/.';

  @override
  Future<int> run() async {
    final paths = ProjectPaths(path);
    final printer = ReportPrinter(_logger, format: outputFormat);

    if (outputFormat == OutputFormat.text) {
      _logger.info('Analyzing project at ${paths.root}');
      _logger.blank();
    }

    final report = _validator.validate(paths);
    printer.validationReport(report);

    if (report.hasErrors) {
      return 1;
    }

    if (outputFormat == OutputFormat.text) {
      _logger.blank();
    }
    final result = await _analyzer.analyze(paths);
    printer.findings(
      result,
      title: 'Primary constructors',
      itemNoun: 'migration candidate',
    );

    return 0;
  }
}
