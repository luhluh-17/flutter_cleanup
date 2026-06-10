import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/output_format.dart';
import '../models/project_paths.dart';
import '../services/directory_tree_builder.dart';
import '../services/ignore_service.dart';
import '../services/logger.dart';
import '../services/project_validator.dart';
import 'base_command.dart';
import 'report_printer.dart';

/// Prints the project's directory structure as an ASCII tree.
///
/// Validates the project, builds a directory-only tree via
/// [DirectoryTreeBuilder], and renders it via [ReportPrinter] — as ASCII art
/// in text mode or as a `{schemaVersion, root, children}` document with
/// `--json`. The command does no traversal itself and the builder does no
/// printing.
///
/// This command only visualizes folder structure: no AST analysis, no
/// architecture rules, no dependency graph.
class TreeCommand extends FlutterCleanupCommand {
  TreeCommand({
    Logger? logger,
    ProjectValidator? validator,
    DirectoryTreeBuilder? builder,
  })  : _logger = logger ?? Logger(),
        _validator = validator ?? const ProjectValidator(),
        _builder = builder ?? const DirectoryTreeBuilder() {
    argParser
      ..addOption(
        'root',
        help: 'Project-relative directory to use as the tree root.',
        defaultsTo: 'lib',
      )
      ..addOption(
        'depth',
        help: 'Maximum directory depth to include (an integer >= 1).',
      );
  }

  final Logger _logger;
  final ProjectValidator _validator;
  final DirectoryTreeBuilder _builder;

  @override
  String get name => 'tree';

  @override
  String get description =>
      'Print the project directory structure as an ASCII tree.';

  /// The `--root` value normalized to a project-relative POSIX path.
  String get _rootRelative {
    final raw = (argResults?['root'] as String? ?? 'lib').replaceAll(r'\', '/');
    final normalized = p.posix.normalize(raw);
    final escapes = normalized.split('/').contains('..');
    if (p.posix.isAbsolute(normalized) || escapes) {
      usageException('--root must be a relative path inside the project.');
    }
    return normalized;
  }

  /// The `--depth` value parsed to an int, or `null` for unlimited.
  int? get _maxDepth {
    final raw = argResults?['depth'] as String?;
    if (raw == null) return null;
    final depth = int.tryParse(raw);
    if (depth == null || depth < 1) {
      usageException('--depth must be an integer >= 1, got "$raw".');
    }
    return depth;
  }

  @override
  Future<int> run() async {
    final maxDepth = _maxDepth;
    final rootRelative = _rootRelative;
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

    final rootDir = p.joinAll([paths.root, ...p.posix.split(rootRelative)]);
    if (!Directory(rootDir).existsSync()) {
      printer.error('Directory not found: $rootRelative');
      return 1;
    }

    final tree = _builder.build(
      projectRoot: paths.root,
      rootDir: rootDir,
      ignoreService: IgnoreService.forProject(paths.root),
      maxDepth: maxDepth,
    );
    printer.tree(tree);

    return 0;
  }
}
