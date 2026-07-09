import '../analysis/analyzer.dart';
import '../analyzers/maintainability/maintainability_analyzer.dart';
import '../analyzers/maintainability/maintainability_config.dart';
import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports maintainability smells (large files, long methods/`build()`s, too
/// many widget classes, deeply nested widget trees) under `lib/`.
///
/// Validates the project, then runs the [MaintainabilityAnalyzer] and renders
/// its findings via [ReportPrinter]. The command does no analysis itself and the
/// analyzer does no printing — each layer has a single responsibility.
class MaintainabilityCommand extends FlutterCleanupCommand {
  MaintainabilityCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? const MaintainabilityAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _analyzer;

  @override
  String get name => 'maintainability';

  @override
  String get description =>
      'Find maintainability smells (large files, long methods, deep widget '
      'nesting) under lib/.';

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

    // Show the accepted-standards legend before the findings so users always
    // see the targets each metric is measured against (text mode only).
    printer.maintainabilityThresholds(MaintainabilityConfig.forProject(paths.root));

    final result = await _analyzer.analyze(paths);
    printer.findings(
      result,
      title: 'Maintainability',
      itemNoun: 'maintainability issue',
    );

    return 0;
  }
}
