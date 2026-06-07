import 'package:args/command_runner.dart';

import '../models/output_format.dart';

/// Base class for commands that operate on a Flutter project directory.
///
/// Centralizes the options shared by project-scoped commands (`scan`,
/// `unused-assets`, and future `unused-files` / `graph` / `doctor`) so each
/// command body stays focused on its own behavior.
///
/// To enable JSON output on a command later, add the flag in that command's
/// constructor (`argParser.addFlag('json', negatable: false)`) and override
/// [outputFormat] to read it — no other layer needs to change.
abstract class FlutterCleanupCommand extends Command<int> {
  FlutterCleanupCommand() {
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to the Flutter project.',
      defaultsTo: '.',
    );
  }

  /// The project path supplied via `--path`, defaulting to the current dir.
  String get path => argResults?['path'] as String? ?? '.';

  /// The format results should be rendered in.
  ///
  /// Defaults to [OutputFormat.text]. Commands that add a `--json` flag
  /// override this to return [OutputFormat.json] when the flag is set.
  OutputFormat get outputFormat => OutputFormat.text;
}
