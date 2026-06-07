/// The severity of a single [ValidationResult].
enum ValidationSeverity {
  /// The check passed with no concerns.
  ok,

  /// The check surfaced a non-fatal concern worth noting.
  warning,

  /// The check failed in a way that should stop further work.
  error,
}

/// The outcome of a single project validation check.
class ValidationResult {
  const ValidationResult({
    required this.label,
    required this.severity,
    this.detail,
  });

  /// Convenience constructor for a passing check.
  const ValidationResult.ok(String label, {String? detail})
      : this(label: label, severity: ValidationSeverity.ok, detail: detail);

  /// Convenience constructor for a warning.
  const ValidationResult.warning(String label, {String? detail})
      : this(label: label, severity: ValidationSeverity.warning, detail: detail);

  /// Convenience constructor for a failing check.
  const ValidationResult.error(String label, {String? detail})
      : this(label: label, severity: ValidationSeverity.error, detail: detail);

  /// A short, human-readable description of what was checked.
  final String label;

  /// How serious the outcome of this check is.
  final ValidationSeverity severity;

  /// Optional additional context (for example, the path that was checked).
  final String? detail;

  /// Whether this check passed (i.e. is not an error).
  bool get passed => severity != ValidationSeverity.error;
}

/// An aggregate of [ValidationResult]s produced by a validation run.
class ValidationReport {
  ValidationReport(this.results);

  /// The individual check results, in the order they were performed.
  final List<ValidationResult> results;

  /// Whether any result is an [ValidationSeverity.error].
  bool get hasErrors =>
      results.any((r) => r.severity == ValidationSeverity.error);

  /// Whether any result is a [ValidationSeverity.warning].
  bool get hasWarnings =>
      results.any((r) => r.severity == ValidationSeverity.warning);
}
