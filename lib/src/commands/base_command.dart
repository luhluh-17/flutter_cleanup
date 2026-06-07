import 'package:args/command_runner.dart';

import '../models/output_format.dart';

/// Base class for commands that operate on a Flutter project directory.
///
/// Centralizes the options shared by project-scoped commands (`scan`,
/// `unused-assets`, and future `unused-files` / `graph` / `doctor`) so each
/// command body stays focused on its own behavior.
///
/// The shared `--json` flag is defined here once, so every subcommand inherits
/// machine-readable output without redefining the flag. Commands pass
/// [outputFormat] through to the [ReportPrinter]; no other layer needs to know
/// about the flag.
abstract class FlutterCleanupCommand extends Command<int> {
  FlutterCleanupCommand() {
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to the Flutter project.',
      defaultsTo: '.',
    );
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit machine-readable JSON instead of human-readable text.',
    );
  }

  /// The project path supplied via `--path`, defaulting to the current dir.
  String get path => argResults?['path'] as String? ?? '.';

  /// The format results should be rendered in, selected by the `--json` flag.
  OutputFormat get outputFormat => (argResults?['json'] as bool? ?? false)
      ? OutputFormat.json
      : OutputFormat.text;
}
