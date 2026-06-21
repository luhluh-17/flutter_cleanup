import 'dart:io';

import '../analysis/analysis_result.dart';
import '../analysis/analyzer.dart';
import '../analyzers/duplicate_code_analyzer.dart';
import '../analyzers/duplicate_widgets_analyzer.dart';
import '../analyzers/maintainability/maintainability_analyzer.dart';
import '../analyzers/unused_assets_analyzer.dart';
import '../analyzers/unused_files_analyzer.dart';
import '../architecture/architecture_analyzer.dart';
import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Runs every analyzer against the project in one pass.
///
/// Validates the project once, then runs each analyzer in turn and renders its
/// findings via [ReportPrinter] under its own heading. This is the convenience
/// "do everything" command; the individual commands remain available when you
/// only want one report. Adding an analyzer to [_sections] is all it takes to
/// include it here.
class AllCommand extends FlutterCleanupCommand {
  AllCommand({
    Logger? logger,
    ProjectValidator? validator,
    Analyzer? unusedAssets,
    Analyzer? unusedFiles,
    Analyzer? duplicateCode,
    Analyzer? duplicateWidgets,
    Analyzer? maintainability,
    Analyzer? architecture,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _unusedAssets = unusedAssets ?? const UnusedAssetsAnalyzer(),
        _unusedFiles = unusedFiles ?? const UnusedFilesAnalyzer(),
        _duplicateCode = duplicateCode ?? const DuplicateCodeAnalyzer(),
        _duplicateWidgets =
            duplicateWidgets ?? const DuplicateWidgetsAnalyzer(),
        _maintainability =
            maintainability ?? const MaintainabilityAnalyzer(),
        _architecture = architecture ?? ArchitectureAnalyzer();

  final Logger _logger;
  final ProjectValidator _validator;
  final Analyzer _unusedAssets;
  final Analyzer _unusedFiles;
  final Analyzer _duplicateCode;
  final Analyzer _duplicateWidgets;
  final Analyzer _maintainability;
  final Analyzer _architecture;

  @override
  String get name => 'all';

  @override
  String get description =>
      'Run all analyzers (unused-assets, unused-files, duplicate-code, '
      'duplicate-widgets, maintainability, architecture).';

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

    final sections = <({Analyzer analyzer, String title, String itemNoun})>[
      (
        analyzer: _unusedAssets,
        title: 'Unused assets',
        itemNoun: 'unused asset',
      ),
      (analyzer: _unusedFiles, title: 'Unused files', itemNoun: 'unused file'),
      (
        analyzer: _duplicateCode,
        title: 'Duplicate code',
        itemNoun: 'duplicate pair',
      ),
      (
        analyzer: _duplicateWidgets,
        title: 'Duplicate Widgets',
        itemNoun: 'duplicate widget pair',
      ),
      (
        analyzer: _maintainability,
        title: 'Maintainability',
        itemNoun: 'maintainability issue',
      ),
      (
        analyzer: _architecture,
        title: 'Architecture violations',
        itemNoun: 'violation',
      ),
    ];

    final hasMain = File(paths.mainEntrypoint).existsSync();

    // Reachability is undefined without an entry point, so the unused-files
    // section is skipped when lib/main.dart is missing. In JSON mode it becomes
    // an empty result; in text mode it becomes an explanatory heading.

    if (outputFormat == OutputFormat.json) {
      final results = <AnalysisResult>[];
      for (final section in sections) {
        if (identical(section.analyzer, _unusedFiles) && !hasMain) {
          results.add(AnalysisResult.empty(_unusedFiles.name));
          continue;
        }
        results.add(await section.analyzer.analyze(paths));
      }
      printer.aggregate(results);
      return 0;
    }

    for (final section in sections) {
      _logger.blank();

      if (identical(section.analyzer, _unusedFiles) && !hasMain) {
        _logger.heading(section.title);
        _logger.info(
            'lib/main.dart not found — skipping reachability analysis.');
        continue;
      }

      final result = await section.analyzer.analyze(paths);
      printer.findings(
        result,
        title: section.title,
        itemNoun: section.itemNoun,
      );
    }

    return 0;
  }
}
