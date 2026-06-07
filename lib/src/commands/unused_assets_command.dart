import 'package:args/command_runner.dart';

import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'report_printer.dart';

/// Reports assets declared in the project that appear to be unused.
///
/// The analysis itself is not implemented yet; for now the command validates
/// the project and reports that asset analysis is pending. The structure is
/// in place so an [Analyzer] can be wired in later without changing the CLI.
class UnusedAssetsCommand extends Command<int> {
  UnusedAssetsCommand({Logger? logger, ProjectValidator? validator})
      : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator() {
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to the Flutter project to analyze.',
      defaultsTo: '.',
    );
  }

  final Logger _logger;
  final ProjectValidator _validator;

  @override
  String get name => 'unused-assets';

  @override
  String get description => 'Find declared assets that are never referenced.';

  @override
  int run() {
    final path = argResults?['path'] as String? ?? '.';
    final paths = ProjectPaths(path);

    _logger.info('Analyzing project at ${paths.root}');
    _logger.blank();

    final report = _validator.validate(paths);
    printValidationReport(_logger, report);

    if (report.hasErrors) {
      return 1;
    }

    _logger.blank();
    _logger.warn('Asset analysis is not yet implemented.');
    return 0;
  }
}
