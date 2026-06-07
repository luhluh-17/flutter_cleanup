import 'package:args/command_runner.dart';

import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'report_printer.dart';

/// Scans a project directory and validates its basic structure.
///
/// This is the entry point for future analysis: once analyzers exist, this
/// command will orchestrate them after the structure has been validated.
class ScanCommand extends Command<int> {
  ScanCommand({Logger? logger, ProjectValidator? validator})
      : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator() {
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to the Flutter project to scan.',
      defaultsTo: '.',
    );
  }

  final Logger _logger;
  final ProjectValidator _validator;

  @override
  String get name => 'scan';

  @override
  String get description =>
      'Scan a Flutter project and validate its structure.';

  @override
  int run() {
    final path = argResults?['path'] as String? ?? '.';
    final paths = ProjectPaths(path);

    _logger.info('Scanning project at ${paths.root}');
    _logger.blank();

    final report = _validator.validate(paths);
    printValidationReport(_logger, report);

    return report.hasErrors ? 1 : 0;
  }
}
