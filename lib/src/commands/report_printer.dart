import 'dart:convert';

import '../analysis/analysis_result.dart';
import '../analyzers/maintainability/maintainability_config.dart';
import '../analyzers/maintainability/models/maintainability_issue.dart';
import '../models/finding.dart';
import '../models/output_format.dart';
import '../models/validation_result.dart';
import '../services/directory_tree_builder.dart';
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

  /// Renders the maintainability thresholds as a reference legend.
  ///
  /// Text mode prints an "Accepted standards (warning / error)" table so users
  /// see the targets each metric is measured against. JSON mode is a no-op — the
  /// legend is diagnostic chrome and is kept out of the machine-readable
  /// document (mirrors how [validationReport] suppresses chrome in JSON).
  void maintainabilityThresholds(MaintainabilityConfig config) {
    switch (format) {
      case OutputFormat.text:
        _maintainabilityThresholdsText(config);
      case OutputFormat.json:
        break;
    }
  }

  void _maintainabilityThresholdsText(MaintainabilityConfig config) {
    _logger.heading('Accepted standards (limit)');
    final rows = _maintainabilityRows(config);
    final labelWidth =
        rows.map((r) => r.header.length).reduce((a, b) => a > b ? a : b);
    for (final r in rows) {
      _logger.plain('  ${r.header.padRight(labelWidth)}   ≤ ${r.limit} ${r.unit}');
    }
    _logger.blank();
  }

  /// Renders maintainability findings grouped by metric category.
  ///
  /// Unlike the generic [findings], the text form prints one sub-section per
  /// metric (in a fixed canonical order), each headed by the metric's accepted
  /// limit — so the report reads as "here is each standard, and where it is
  /// exceeded". JSON mode is identical to [findings] (a single analyzer
  /// document), since grouping is a text-only presentation concern.
  void maintainabilityFindings(
    AnalysisResult result,
    MaintainabilityConfig config,
  ) {
    switch (format) {
      case OutputFormat.text:
        _maintainabilityFindingsText(result, config);
      case OutputFormat.json:
        _logger.plain(_encoder.convert({
          'schemaVersion': _schemaVersion,
          ...result.toJson(),
        }));
    }
  }

  void _maintainabilityFindingsText(
    AnalysisResult result,
    MaintainabilityConfig config,
  ) {
    _logger.heading('Maintainability');

    final byRule = <String, List<Finding>>{};
    for (final finding in result.findings) {
      byRule.putIfAbsent(finding.rule, () => []).add(finding);
    }

    var first = true;
    for (final row in _maintainabilityRows(config)) {
      final group = byRule[row.rule];
      if (group == null || group.isEmpty) continue;
      if (!first) _logger.blank();
      first = false;
      _logger.plain('${row.header} (≤ ${row.limit} ${row.unit})');
      _renderFindingGroup(group);
    }
    _logger.blank();

    final count = result.findings.length;
    if (count == 0) {
      _logger.success('No maintainability issues found.');
    } else {
      _logger.warn(
          '$count maintainability issue${count == 1 ? '' : 's'} found.');
    }
  }

  /// Renders one metric's findings, indented under its sub-heading. Identical
  /// issues (same rule + message + severity) are collapsed into one line with an
  /// occurrence list, matching [_findingsText].
  void _renderFindingGroup(List<Finding> findings) {
    final groups = <Finding, List<Finding>>{};
    for (final finding in findings) {
      final group = groups.keys.firstWhere(
        (g) =>
            g.rule == finding.rule &&
            g.message == finding.message &&
            g.severity == finding.severity,
        orElse: () => finding,
      );
      groups.putIfAbsent(group, () => []).add(finding);
    }
    final sortedGroups = groups.entries.toList()
      ..sort((a, b) => a.key.message.compareTo(b.key.message));

    for (final entry in sortedGroups) {
      final items = entry.value
        ..sort((a, b) {
          final byPath = a.path.compareTo(b.path);
          if (byPath != 0) return byPath;
          return (a.line ?? 0).compareTo(b.line ?? 0);
        });
      final first = items.first;
      final headline = items.length == 1
          ? '${_location(first)} — ${first.message}'
          : '${first.message} (${items.length} occurrences)';
      switch (first.severity) {
        case Severity.info:
          _logger.info('  $headline');
        case Severity.warning:
          _logger.warn('  $headline');
        case Severity.error:
          _logger.error('  $headline');
      }
      if (items.length > 1) {
        for (final finding in items) {
          _logger.plain('      ${_location(finding)}');
        }
      }
      if (first.recommendation != null) {
        _logger.plain('      ↳ ${first.recommendation}');
      }
    }
  }

  /// The maintainability metrics in canonical report order, each paired with its
  /// stable rule id, display header, active limit, and unit. Single source of
  /// truth for both the legend and the grouped findings sub-headings.
  static List<({String rule, String header, int limit, String unit})>
      _maintainabilityRows(MaintainabilityConfig config) => [
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.folderFileCount),
              header: 'Folder',
              limit: config.folderFiles,
              unit: 'files',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.publicClassCount),
              header: 'Public classes',
              limit: config.maxPublicClasses,
              unit: 'per file',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.widgetFileLength),
              header: 'Widget file',
              limit: config.widgetFileLines,
              unit: 'lines',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.controllerLength),
              header: 'Controller',
              limit: config.controllerLines,
              unit: 'lines',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.fileLength),
              header: 'File',
              limit: config.fileLines,
              unit: 'lines',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.buildMethodLength),
              header: 'build()',
              limit: config.buildMethodLines,
              unit: 'lines',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.methodLength),
              header: 'Method',
              limit: config.methodLines,
              unit: 'lines',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.constructorParams),
              header: 'Constructor params',
              limit: config.constructorParams,
              unit: 'params',
            ),
            (
              rule: MaintainabilityIssue.ruleFor(
                  MaintainabilityIssueKind.nestingDepth),
              header: 'Widget nesting',
              limit: config.widgetNestingDepth,
              unit: 'levels',
            ),
          ];

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

  /// Renders a directory tree rooted at [root].
  ///
  /// Text mode prints ASCII-art lines (see [renderAsciiTree]); JSON mode emits
  /// a `{schemaVersion, root, children}` document where `root` is the
  /// project-relative POSIX path of the tree root.
  void tree(DirectoryTreeNode root) {
    switch (format) {
      case OutputFormat.text:
        for (final line in renderAsciiTree(root)) {
          _logger.plain(line);
        }
      case OutputFormat.json:
        _logger.plain(_encoder.convert({
          'schemaVersion': _schemaVersion,
          'root': root.name,
          'children': [for (final child in root.children) child.toJson()],
        }));
    }
  }

  /// Renders a standalone error [message].
  ///
  /// Text mode prints a red error line; JSON mode emits the same
  /// `{ "error": { "message": ... } }` document shape as a failed
  /// [validationReport], so consumers handle one error contract.
  void error(String message) {
    switch (format) {
      case OutputFormat.text:
        _logger.error(message);
      case OutputFormat.json:
        _logger.plain(_encoder.convert({
          'schemaVersion': _schemaVersion,
          'error': {'message': message},
        }));
    }
  }

  void _findingsText(
    AnalysisResult result, {
    required String title,
    required String itemNoun,
  }) {
    _logger.heading(title);

    // Identical issues (same rule + message + severity) are grouped so a rule
    // firing on many lines reads as one issue with a location list, not a wall
    // of repeats. Groups are ordered by rule code then message; locations by
    // path then line. A single-occurrence group keeps the classic
    // `path:line — message` line.
    final groups = <Finding, List<Finding>>{};
    for (final finding in result.findings) {
      final group = groups.keys.firstWhere(
        (g) =>
            g.rule == finding.rule &&
            g.message == finding.message &&
            g.severity == finding.severity,
        orElse: () => finding,
      );
      groups.putIfAbsent(group, () => []).add(finding);
    }
    final sortedGroups = groups.entries.toList()
      ..sort((a, b) {
        final byRule = a.key.rule.compareTo(b.key.rule);
        if (byRule != 0) return byRule;
        return a.key.message.compareTo(b.key.message);
      });

    for (final entry in sortedGroups) {
      final findings = entry.value
        ..sort((a, b) {
          final byPath = a.path.compareTo(b.path);
          if (byPath != 0) return byPath;
          return (a.line ?? 0).compareTo(b.line ?? 0);
        });
      final first = findings.first;

      final headline = findings.length == 1
          ? '${_location(first)} — ${first.message}'
          : '${first.message} (${findings.length} occurrences)';
      switch (first.severity) {
        case Severity.info:
          _logger.info(headline);
        case Severity.warning:
          _logger.warn(headline);
        case Severity.error:
          _logger.error(headline);
      }
      if (findings.length > 1) {
        for (final finding in findings) {
          _logger.plain('    ${_location(finding)}');
        }
      }
      if (first.recommendation != null) {
        _logger.plain('    ↳ ${first.recommendation}');
      }
    }
    _logger.blank();

    final count = result.findings.length;
    final plural = '${itemNoun}s';
    if (count == 0) {
      _logger.success('No $plural found.');
    } else {
      final groupCount = sortedGroups.length;
      final distinct = groupCount < count
          ? ' ($groupCount distinct issue${groupCount == 1 ? '' : 's'})'
          : '';
      _logger.warn('$count ${count == 1 ? itemNoun : plural} found$distinct.');
    }
  }

  /// `path:line[:column]` — the same convention as dart analyze, so the
  /// offending line is actionable straight from the terminal.
  static String _location(Finding finding) => finding.line == null
      ? finding.path
      : '${finding.path}:${finding.line}'
          '${finding.column == null ? '' : ':${finding.column}'}';

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
