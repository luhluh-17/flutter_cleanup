import '../architecture/architecture_analyzer.dart';
import '../architecture/architecture_result.dart';
import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Reports Clean Architecture + Feature-Based + Riverpod violations
/// (ARCH101–503) under `lib/`.
///
/// Validates the project, runs the [ArchitectureAnalyzer], prints the
/// architecture score and findings via [ReportPrinter], and — with `--report` —
/// the feature-dependency tree. The command does no analysis itself; the
/// analyzer does no printing.
class ArchitectureCommand extends FlutterCleanupCommand {
  ArchitectureCommand({
    Logger? logger,
    ProjectValidator? validator,
    ArchitectureAnalyzer? analyzer,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _analyzer = analyzer ?? ArchitectureAnalyzer() {
    argParser.addFlag(
      'report',
      negatable: false,
      help: 'Also print the feature-dependency tree built from the import graph.',
    );
  }

  final Logger _logger;
  final ProjectValidator _validator;
  final ArchitectureAnalyzer _analyzer;

  bool get _report => argResults?['report'] as bool? ?? false;

  @override
  String get name => 'architecture';

  @override
  String get description =>
      'Detect Clean Architecture / Riverpod violations (ARCH101–503) in lib/.';

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
    if (report.hasErrors) return 1;

    final result = await _analyzer.analyze(paths);

    if (outputFormat == OutputFormat.text) {
      _logger.blank();
      _printScore(result);
    }

    printer.findings(
      result,
      title: 'Architecture violations',
      itemNoun: 'violation',
    );

    if (_report && outputFormat == OutputFormat.text) {
      _logger.blank();
      _logger.heading('Feature dependencies');
      _logger.plain(result.renderDependencyReport());
    }

    return 0;
  }

  void _printScore(ArchitectureResult result) {
    _logger.heading('Architecture score');
    final counts = result.severityCounts;
    _logger.info('Score: ${result.score}/100');
    _logger.info('${counts.errors} error(s), ${counts.warnings} warning(s), '
        '${counts.infos} info(s).');
    _logger.blank();
  }
}
