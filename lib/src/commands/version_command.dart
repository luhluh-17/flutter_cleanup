import 'package:args/command_runner.dart';

import '../services/logger.dart';
import '../version.dart';

/// Prints the installed version of the CLI.
class VersionCommand extends Command<int> {
  VersionCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'version';

  @override
  String get description => 'Print the flutter_cleanup version.';

  @override
  int run() {
    _logger.plain('flutter_cleanup $packageVersion');
    return 0;
  }
}
