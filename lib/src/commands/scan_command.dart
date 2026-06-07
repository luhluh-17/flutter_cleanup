import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Scans a project directory and validates its basic structure.
///
/// This is the entry point for future analysis: once analyzers exist, this
/// command will orchestrate them after the structure has been validated.
class ScanCommand extends FlutterCleanupCommand {
  ScanCommand({Logger? logger, ProjectValidator? validator})
      : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator();

  final Logger _logger;
  final ProjectValidator _validator;

  @override
  String get name => 'scan';

  @override
  String get description =>
      'Scan a Flutter project and validate its structure.';

  @override
  int run() {
    final paths = ProjectPaths(path);

    _logger.info('Scanning project at ${paths.root}');
    _logger.blank();

    final report = _validator.validate(paths);
    ReportPrinter(_logger, format: outputFormat).validationReport(report);

    return report.hasErrors ? 1 : 0;
  }
}
