import 'package:args/command_runner.dart';

import '../commands/all_command.dart';
import '../commands/architecture_command.dart';
import '../commands/duplicate_code_command.dart';
import '../commands/duplicate_widgets_command.dart';
import '../commands/scan_command.dart';
import '../commands/tree_command.dart';
import '../commands/unused_assets_command.dart';
import '../commands/unused_files_command.dart';
import '../commands/version_command.dart';
import '../models/project_paths.dart';
import '../services/logger.dart';

/// Builds and runs the flutter_cleanup command-line interface.
///
/// Wraps the `args` [CommandRunner] and registers all available commands.
/// To add a new command, implement a [Command] and add it in [_buildRunner];
/// nothing else in the CLI core needs to change.
class CliRunner {
  CliRunner({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  CommandRunner<int> _buildRunner() {
    final runner = CommandRunner<int>(
      'flutter_cleanup',
      'Identify unused files, assets, dead code, and dependency '
          'relationships in Flutter projects.',
    )
      ..addCommand(ScanCommand(logger: _logger))
      ..addCommand(DuplicateCodeCommand(logger: _logger))
      ..addCommand(DuplicateWidgetsCommand(logger: _logger))
      ..addCommand(UnusedAssetsCommand(logger: _logger))
      ..addCommand(UnusedFilesCommand(logger: _logger))
      ..addCommand(ArchitectureCommand(logger: _logger))
      ..addCommand(TreeCommand(logger: _logger))
      ..addCommand(AllCommand(logger: _logger))
      ..addCommand(VersionCommand(logger: _logger));
    return runner;
  }

  /// Parses [args], dispatches to the matching command, and returns an
  /// process exit code (0 = success).
  Future<int> run(List<String> args) async {
    try {
      final result = await _buildRunner().run(args);
      return result ?? 0;
    } on InvalidProjectPathException catch (e) {
      _logger.error(e.message);
      return 66; // EX_NOINPUT — the input path cannot be used.
    } on UsageException catch (e) {
      _logger.error(e.message);
      _logger.blank();
      _logger.plain(e.usage);
      return 64; // EX_USAGE — invalid command-line usage.
    }
  }
}
