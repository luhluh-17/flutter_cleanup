import '../analysis/analyzer.dart';
import '../analyzers/duplicate_code_analyzer.dart';
import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports highly similar (likely copy-pasted) Dart files under `lib/`.
///
/// Validates the project, then runs the [DuplicateCodeAnalyzer] and renders its
/// findings via [ReportPrinter]. The command does no analysis itself and the
/// analyzer does no printing — each layer has a single responsibility.
class DuplicateCodeCommand extends FlutterCleanupCommand {
  DuplicateCodeCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? const DuplicateCodeAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _analyzer;

  @override
  String get name => 'duplicate-code';

  @override
  String get description =>
      'Find highly similar (likely copy-pasted) Dart files under lib/.';

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
    printer.findings(result, title: 'Duplicate code', itemNoun: 'duplicate pair');

    return 0;
  }
}
