/// How serious a [Finding] reported by an analyzer is.
enum Severity {
  info,
  warning,
  error,
}

/// A single, structured result produced by an analyzer.
///
/// Findings are the common currency every analyzer emits. Keeping them in a
/// single, uniform shape (rather than ad-hoc strings) lets every output format
/// — text today, JSON later — render them the same way.
class Finding {
  final String rule;
  final String path;
  final Severity severity;
  final String message;

  const Finding({
    required this.rule,
    required this.path,
    required this.severity,
    required this.message,
  });
}
