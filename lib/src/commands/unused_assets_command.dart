import '../analysis/analyzer.dart';
import '../analyzers/unused_assets_analyzer.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports assets declared in the project that appear to be unused.
///
/// Validates the project, then runs the [UnusedAssetsAnalyzer] and renders its
/// findings via [ReportPrinter]. The command does no analysis itself and the
/// analyzer does no printing — each layer has a single responsibility.
class UnusedAssetsCommand extends FlutterCleanupCommand {
  UnusedAssetsCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? const UnusedAssetsAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _analyzer;

  @override
  String get name => 'unused-assets';

  @override
  String get description => 'Find declared assets that are never referenced.';

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
    printer.findings(result);

    return 0;
  }
}
