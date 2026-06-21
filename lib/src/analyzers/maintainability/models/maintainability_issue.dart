import '../../../models/finding.dart';

/// The maintainability metric a [MaintainabilityIssue] reports on.
enum MaintainabilityIssueKind {
  fileLength,
  methodLength,
  buildMethodLength,
  widgetCount,
  nestingDepth,
}

/// A single measured maintainability problem in one file.
///
/// This is the analyzer's *internal* representation: the analyzer measures a
/// metric, decides the [severity], and records the [value] plus an optional
/// [subject] (method/widget name) and [line]. [toFinding] turns it into the
/// uniform [Finding] the rest of the tool renders — keeping all message and
/// recommendation wording in one place so the analyzer stays focused on
/// measurement.
class MaintainabilityIssue {
  const MaintainabilityIssue({
    required this.kind,
    required this.severity,
    required this.value,
    this.subject,
    this.line,
  });

  /// The rule name shared by every maintainability finding.
  static const String rule = 'maintainability';

  final MaintainabilityIssueKind kind;
  final Severity severity;

  /// The measured count that crossed a threshold (lines, widgets, or depth).
  final int value;

  /// Method or widget name the issue is about, when applicable.
  final String? subject;

  /// 1-based source line the issue points at, when applicable.
  final int? line;

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
      case MaintainabilityIssueKind.fileLength:
        return 'File contains $value lines.';
      case MaintainabilityIssueKind.methodLength:
        return 'Method $subject() contains $value lines.';
      case MaintainabilityIssueKind.buildMethodLength:
        return 'build() method contains $value lines.';
      case MaintainabilityIssueKind.widgetCount:
        return 'File contains $value widget classes.';
      case MaintainabilityIssueKind.nestingDepth:
        return 'Maximum widget nesting depth is $value.';
    }
  }

  String get _recommendation {
    switch (kind) {
      case MaintainabilityIssueKind.fileLength:
        return 'Split into smaller widgets or feature-specific files.';
      case MaintainabilityIssueKind.methodLength:
        return 'Extract helper methods.';
      case MaintainabilityIssueKind.buildMethodLength:
        return 'Extract reusable widgets.';
      case MaintainabilityIssueKind.widgetCount:
        return 'Move widgets into separate files.';
      case MaintainabilityIssueKind.nestingDepth:
        return 'Extract nested sections into dedicated widgets.';
    }
  }
}
