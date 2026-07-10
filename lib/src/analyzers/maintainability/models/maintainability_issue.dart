import '../../../models/finding.dart';

/// The maintainability metric a [MaintainabilityIssue] reports on.
///
/// Each kind maps to a distinct, stable [rule] id (see [MaintainabilityIssue.rule])
/// so findings can be grouped by category in the report and machine-readable
/// consumers get a specific rule rather than one shared `maintainability` value.
enum MaintainabilityIssueKind {
  widgetFileLength,
  controllerLength,
  fileLength,
  buildMethodLength,
  methodLength,
  nestingDepth,
  publicClassCount,
  constructorParams,
  folderFileCount,
}

/// A single measured maintainability problem in one file (or folder).
///
/// This is the analyzer's *internal* representation: the analyzer measures a
/// metric, records the [value] it saw and the [limit] it was measured against,
/// plus an optional [subject] (method/constructor/class name) and [line].
/// [toFinding] turns it into the uniform [Finding] the rest of the tool renders —
/// keeping all message and recommendation wording in one place so the analyzer
/// stays focused on measurement.
///
/// Every metric is a single accepted maximum: [value] is only ever recorded when
/// it is *strictly greater than* [limit], and every finding is reported at
/// [Severity.warning].
class MaintainabilityIssue {
  const MaintainabilityIssue({
    required this.kind,
    required this.value,
    required this.limit,
    this.subject,
    this.line,
  });

  final MaintainabilityIssueKind kind;

  /// The measured count that exceeded [limit] (lines, classes, params, depth).
  final int value;

  /// The accepted maximum for this metric, shown in the message as the limit.
  final int limit;

  /// Method, constructor, or class name the issue is about, when applicable.
  final String? subject;

  /// 1-based source line the issue points at, when applicable.
  final int? line;

  /// Every maintainability finding is a smell, not a compile error.
  static const Severity severity = Severity.warning;

  /// The stable rule id for [kind], used both for grouping the text report and
  /// as the `rule` field of the emitted [Finding].
  String get rule => ruleFor(kind);

  /// Maps a [MaintainabilityIssueKind] to its stable rule id.
  static String ruleFor(MaintainabilityIssueKind kind) {
    switch (kind) {
      case MaintainabilityIssueKind.widgetFileLength:
        return 'widget_file_length';
      case MaintainabilityIssueKind.controllerLength:
        return 'controller_length';
      case MaintainabilityIssueKind.fileLength:
        return 'file_length';
      case MaintainabilityIssueKind.buildMethodLength:
        return 'build_method_length';
      case MaintainabilityIssueKind.methodLength:
        return 'method_length';
      case MaintainabilityIssueKind.nestingDepth:
        return 'widget_nesting_depth';
      case MaintainabilityIssueKind.publicClassCount:
        return 'public_class_count';
      case MaintainabilityIssueKind.constructorParams:
        return 'constructor_params';
      case MaintainabilityIssueKind.folderFileCount:
        return 'folder_file_count';
    }
  }

  /// Renders this issue as a [Finding] rooted at [path] (project-relative POSIX).
  Finding toFinding(String path) => Finding(
        rule: rule,
        path: path,
        severity: severity,
        message: _message,
        line: line,
        recommendation: _recommendation,
      );

  String get _message {
    switch (kind) {
      case MaintainabilityIssueKind.widgetFileLength:
        return 'Widget file contains $value lines$_limit.';
      case MaintainabilityIssueKind.controllerLength:
        return 'Controller contains $value lines$_limit.';
      case MaintainabilityIssueKind.fileLength:
        return 'File contains $value lines$_limit.';
      case MaintainabilityIssueKind.buildMethodLength:
        return 'build() method contains $value lines$_limit.';
      case MaintainabilityIssueKind.methodLength:
        return 'Method $subject() contains $value lines$_limit.';
      case MaintainabilityIssueKind.nestingDepth:
        return 'Maximum widget nesting depth is $value$_limit.';
      case MaintainabilityIssueKind.publicClassCount:
        return 'File declares $value public classes$_limit.';
      case MaintainabilityIssueKind.constructorParams:
        return 'Constructor $subject has $value parameters$_limit.';
      case MaintainabilityIssueKind.folderFileCount:
        return 'Folder contains $value Dart files$_limit.';
    }
  }

  /// The accepted maximum, rendered as ` (limit: N)`.
  String get _limit => ' (limit: $limit)';

  String get _recommendation {
    switch (kind) {
      case MaintainabilityIssueKind.widgetFileLength:
      case MaintainabilityIssueKind.fileLength:
        return 'Split into smaller widgets or feature-specific files.';
      case MaintainabilityIssueKind.controllerLength:
        return 'Split responsibilities into smaller controllers or services.';
      case MaintainabilityIssueKind.buildMethodLength:
        return 'Extract reusable widgets.';
      case MaintainabilityIssueKind.methodLength:
        return 'Extract helper methods.';
      case MaintainabilityIssueKind.nestingDepth:
        return 'Extract nested sections into dedicated widgets.';
      case MaintainabilityIssueKind.publicClassCount:
        return 'Move each public class into its own file.';
      case MaintainabilityIssueKind.constructorParams:
        return 'Group related parameters into a parameter object.';
      case MaintainabilityIssueKind.folderFileCount:
        return 'Split into sub-folders.';
    }
  }
}
