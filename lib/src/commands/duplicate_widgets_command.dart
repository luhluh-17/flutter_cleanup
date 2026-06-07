import '../analysis/analyzer.dart';
import '../analyzers/duplicate_widgets_analyzer.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports structurally highly similar (likely copy-pasted) Flutter widgets
/// under `lib/`.
///
/// Validates the project, then runs the [DuplicateWidgetsAnalyzer] and renders
/// its findings via [ReportPrinter]. The command does no analysis itself and the
/// analyzer does no printing — each layer has a single responsibility.
class DuplicateWidgetsCommand extends FlutterCleanupCommand {
  DuplicateWidgetsCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? const DuplicateWidgetsAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _analyzer;

  @override
  String get name => 'duplicate-widgets';

  @override
  String get description =>
      'Find structurally highly similar Flutter widgets under lib/.';

  @override
  Future<int> run() async {
    final paths = ProjectPaths(path);

    _logger.info('Analyzing project at ${paths.root}');
    _logger.blank();

    final report = _validator.validate(paths);
    final printer = ReportPrinter(_logger, format: outputFormat);
    printer.validationReport(report);

    if (report.hasErrors) {
      return 1;
    }

    _logger.blank();
    final result = await _analyzer.analyze(paths);
    printer.findings(
      result,
      title: 'Duplicate Widgets',
      itemNoun: 'duplicate widget pair',
    );

    return 0;
  }
}
