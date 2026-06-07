import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports assets declared in the project that appear to be unused.
///
/// The analysis itself is not implemented yet; for now the command validates
/// the project and reports that asset analysis is pending. The structure is
/// in place so an `Analyzer` can be wired in later without changing the CLI.
class UnusedAssetsCommand extends FlutterCleanupCommand {
  UnusedAssetsCommand({Logger? logger, ProjectValidator? validator})
      : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator();

  final Logger _logger;
  final ProjectValidator _validator;

  @override
  String get name => 'unused-assets';

  @override
  String get description => 'Find declared assets that are never referenced.';

  @override
  int run() {
    final paths = ProjectPaths(path);

    _logger.info('Analyzing project at ${paths.root}');
    _logger.blank();

    final report = _validator.validate(paths);
    ReportPrinter(_logger, format: outputFormat).validationReport(report);

    if (report.hasErrors) {
      return 1;
    }

    _logger.blank();
    _logger.warn('Asset analysis is not yet implemented.');
    return 0;
  }
}
