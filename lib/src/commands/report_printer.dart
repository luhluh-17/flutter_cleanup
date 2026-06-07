import '../models/validation_result.dart';
import '../services/logger.dart';

/// Renders a [ValidationReport] to the terminal via [logger].
///
/// Shared by commands that validate the project so the output stays
/// consistent across the CLI.
void printValidationReport(Logger logger, ValidationReport report) {
  logger.heading('Project validation');
  for (final result in report.results) {
    final line =
        result.detail == null ? result.label : '${result.label} (${result.detail})';
    switch (result.severity) {
      case ValidationSeverity.ok:
        logger.success(line);
      case ValidationSeverity.warning:
        logger.warn(line);
      case ValidationSeverity.error:
        logger.error(line);
    }
  }
  logger.blank();

  if (report.hasErrors) {
    logger.error('Validation failed — this does not look like a valid '
        'Flutter/Dart project.');
  } else if (report.hasWarnings) {
    logger.warn('Validation passed with warnings.');
  } else {
    logger.success('Validation passed.');
  }
}
