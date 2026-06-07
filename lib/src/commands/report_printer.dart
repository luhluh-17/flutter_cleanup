import '../analysis/analysis_result.dart';
import '../models/finding.dart';
import '../models/output_format.dart';
import '../models/validation_result.dart';
import '../services/logger.dart';

/// Renders command results to the terminal in a chosen [OutputFormat].
///
/// Today only [OutputFormat.text] is implemented. The format switch is the
/// single place a JSON renderer slots in later, so commands can already be
/// written to pass their [OutputFormat] through without changing their logic.
class ReportPrinter {
  ReportPrinter(this._logger, {this.format = OutputFormat.text});

  final Logger _logger;
  final OutputFormat format;

  /// Renders a [ValidationReport].
  void validationReport(ValidationReport report) {
    switch (format) {
      case OutputFormat.text:
        _validationReportText(report);
      case OutputFormat.json:
        throw UnimplementedError('JSON output is not implemented yet.');
    }
  }

  /// Renders the findings of an [AnalysisResult].
  void findings(AnalysisResult result) {
    switch (format) {
      case OutputFormat.text:
        _findingsText(result);
      case OutputFormat.json:
        throw UnimplementedError('JSON output is not implemented yet.');
    }
  }

  void _findingsText(AnalysisResult result) {
    _logger.heading('Unused assets');
    for (final finding in result.findings) {
      final line = '${finding.path} — ${finding.message}';
      switch (finding.severity) {
        case Severity.info:
          _logger.info(line);
        case Severity.warning:
          _logger.warn(line);
        case Severity.error:
          _logger.error(line);
      }
    }
    _logger.blank();

    final count = result.findings.length;
    if (count == 0) {
      _logger.success('No unused assets found.');
    } else {
      _logger.warn('$count unused asset${count == 1 ? '' : 's'} found.');
    }
  }

  void _validationReportText(ValidationReport report) {
    _logger.heading('Project validation');
    for (final result in report.results) {
      final line = result.detail == null
          ? result.label
          : '${result.label} (${result.detail})';
      switch (result.severity) {
        case ValidationSeverity.ok:
          _logger.success(line);
        case ValidationSeverity.warning:
          _logger.warn(line);
        case ValidationSeverity.error:
          _logger.error(line);
      }
    }
    _logger.blank();

    if (report.hasErrors) {
      _logger.error('Validation failed — this does not look like a valid '
          'Flutter/Dart project.');
    } else if (report.hasWarnings) {
      _logger.warn('Validation passed with warnings.');
    } else {
      _logger.success('Validation passed.');
    }
  }
}
