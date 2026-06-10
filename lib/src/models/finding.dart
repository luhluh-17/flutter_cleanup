/// How serious a [Finding] reported by an analyzer is.
enum Severity {
  info,
  warning,
  error,
}

/// How certain an analyzer is that a [Finding] is a real problem.
///
/// flutter_cleanup performs *syntactic* AST analysis (no element/type
/// resolution), so some rules are inherently heuristic. Grading confidence —
/// SonarQube-style — keeps the tool honest: a `*RepositoryImpl()` literal is
/// [high], while "this notifier seems to build its own dependency" is [medium].
enum Confidence {
  high,
  medium,
  low,
}

/// A single, structured result produced by an analyzer.
///
/// Findings are the common currency every analyzer emits. Keeping them in a
/// single, uniform shape (rather than ad-hoc strings) lets every output format
/// — text today, JSON later — render them the same way.
///
/// [line]/[column] (1-based) and [confidence] are optional: analyzers that work
/// at file granularity (unused-assets, duplicate-code, …) leave them null, and
/// they are omitted from [toJson] so that output stays byte-compatible with
/// analyzers that don't set them. Architecture rules populate them so the VS
/// Code extension can place diagnostics on the exact offending line.
class Finding {
  final String rule;
  final String path;
  final Severity severity;
  final String message;
  final int? line;
  final int? column;
  final Confidence? confidence;

  const Finding({
    required this.rule,
    required this.path,
    required this.severity,
    required this.message,
    this.line,
    this.column,
    this.confidence,
  });

  /// Serializes this finding to a JSON-encodable map.
  ///
  /// [severity] is emitted as its lowercase enum name (`info`/`warning`/
  /// `error`) so consumers get a stable, machine-readable value. Optional
  /// fields ([line], [column], [confidence]) are only included when set, so
  /// analyzers that don't use them produce the same document as before.
  Map<String, dynamic> toJson() => {
        'rule': rule,
        'path': path,
        'severity': severity.name,
        'message': message,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
        if (confidence != null) 'confidence': confidence!.name,
      };
}
