/// Public API for the flutter_cleanup CLI framework.
library;

export 'src/analysis/analysis_result.dart';
export 'src/analysis/analyzer.dart';
export 'src/analysis/path_utils.dart';
export 'src/analyzers/duplicate_code_analyzer.dart';
export 'src/analyzers/unused_assets_analyzer.dart';
export 'src/analyzers/unused_files_analyzer.dart';
export 'src/cli/cli_runner.dart';
export 'src/commands/base_command.dart';
export 'src/commands/report_printer.dart';
export 'src/commands/duplicate_code_command.dart';
export 'src/commands/scan_command.dart';
export 'src/commands/unused_assets_command.dart';
export 'src/commands/unused_files_command.dart';
export 'src/commands/version_command.dart';
export 'src/models/finding.dart';
export 'src/models/output_format.dart';
export 'src/models/project_paths.dart';
export 'src/models/validation_result.dart';
export 'src/services/ignore_service.dart';
export 'src/services/logger.dart';
export 'src/services/project_validator.dart';
export 'src/version.dart';
