import 'dart:convert';

import '../analysis/analysis_result.dart';
import '../models/finding.dart';
import '../models/output_format.dart';
import '../models/validation_result.dart';
import '../services/logger.dart';

/// Renders command results to the terminal in a chosen [OutputFormat].
///
/// The format switch is the single place where text and JSON rendering diverge,
/// so commands pass their [OutputFormat] through without changing their logic.
/// Text mode prints human-readable, colorized sections; JSON mode prints a
/// single valid JSON document with no banners, colors, or separators.
class ReportPrinter {
  ReportPrinter(this._logger, {this.format = OutputFormat.text});

  final Logger _logger;
  final OutputFormat format;

  /// Pretty-printer shared by every JSON document this renderer emits.
  static const _encoder = JsonEncoder.withIndent('  ');

  /// Version of the JSON contract. Added at the document/envelope level so
  /// consumers can evolve safely; nested results do not repeat it.
  static const _schemaVersion = 1;

  /// Renders a [ValidationReport].
  ///
  /// In JSON mode the report is treated as diagnostic chrome and is suppressed,
  /// except on failure: a `{ "error": { "message": ... } }` document is emitted
  /// so consumers get a useful message instead of empty output.
  void validationReport(ValidationReport report) {
    switch (format) {
      case OutputFormat.text:
        _validationReportText(report);
      case OutputFormat.json:
        if (report.hasErrors) {
          final firstError = report.results
              .firstWhere((r) => r.severity == ValidationSeverity.error);
          final message = firstError.detail == null
              ? firstError.label
              : '${firstError.label} (${firstError.detail})';
          _logger.plain(_encoder.convert({
            'schemaVersion': _schemaVersion,
            'error': {'message': message},
          }));
        }
    }
  }

  /// Renders the findings of an [AnalysisResult].
  ///
  /// [title] is the section heading; [itemNoun] is the singular noun used in the
  /// summary line (e.g. `'unused asset'`), pluralized by appending `s`. In JSON
  /// mode [title] and [itemNoun] are ignored — a single-analyzer document is
  /// emitted instead.
  void findings(
    AnalysisResult result, {
    required String title,
    required String itemNoun,
  }) {
    switch (format) {
      case OutputFormat.text:
        _findingsText(result, title: title, itemNoun: itemNoun);
      case OutputFormat.json:
        _logger.plain(_encoder.convert({
          'schemaVersion': _schemaVersion,
          ...result.toJson(),
        }));
    }
  }

  /// Renders several [AnalysisResult]s as a single aggregate JSON document.
  ///
  /// Used by the `all` command in JSON mode. Text mode renders per-section via
  /// [findings] instead, so this method is a no-op there.
  void aggregate(List<AnalysisResult> results) {
    switch (format) {
      case OutputFormat.text:
        // Not used in text mode; AllCommand renders per-section instead.
        break;
      case OutputFormat.json:
        _logger.plain(_encoder.convert({
          'schemaVersion': _schemaVersion,
          'results': [for (final r in results) r.toJson()],
        }));
    }
  }

  void _findingsText(
    AnalysisResult result, {
    required String title,
    required String itemNoun,
  }) {
    _logger.heading(title);
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
    final plural = '${itemNoun}s';
    if (count == 0) {
      _logger.success('No $plural found.');
    } else {
      _logger.warn('$count ${count == 1 ? itemNoun : plural} found.');
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
