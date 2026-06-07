import 'dart:io';

import '../analysis/analysis_result.dart';
import '../analysis/analyzer.dart';
import '../analyzers/unused_files_analyzer.dart';
import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports Dart files under `lib/` that are unreachable from `lib/main.dart`.
///
/// Validates the project, then runs the [UnusedFilesAnalyzer] and renders its
/// findings via [ReportPrinter]. The command does no analysis itself and the
/// analyzer does no printing — each layer has a single responsibility.
class UnusedFilesCommand extends FlutterCleanupCommand {
  UnusedFilesCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? const UnusedFilesAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _analyzer;

  @override
  String get name => 'unused-files';

  @override
  String get description =>
      'Find Dart files under lib/ unreachable from lib/main.dart.';

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
    if (!File(paths.mainEntrypoint).existsSync()) {
      // Reachability is undefined without an entry point. In text mode say so;
      // in JSON mode emit an empty result so the contract stays consistent and
      // consumers need no analyzer-specific special-casing.
      if (outputFormat == OutputFormat.text) {
        _logger.info('lib/main.dart not found — skipping reachability analysis.');
      } else {
        printer.findings(
          AnalysisResult.empty(_analyzer.name),
          title: 'Unused files',
          itemNoun: 'unused file',
        );
      }
      return 0;
    }

    final result = await _analyzer.analyze(paths);
    printer.findings(result, title: 'Unused files', itemNoun: 'unused file');

    return 0;
  }
}
