/**
 * Pure mapping from `flutter_cleanup` findings to diagnostic data.
 *
 * This module deliberately imports nothing from `vscode` so it can be unit
 * tested in plain Node (the `vscode` module only exists inside the Extension
 * Host). The thin adapter that turns [DiagnosticData] into `vscode.Diagnostic`
 * lives in `architectureDiagnostics.ts`.
 */

/** A single finding as emitted by the CLI's JSON output. */
export interface ArchFinding {
  rule: string;
  path: string;
  severity: string;
  message: string;
  line?: number;
  column?: number;
  confidence?: string;
}

/** The architecture analyzer's JSON document (the subset we consume). */
export interface ArchitectureResultJson {
  analyzer?: string;
  findings?: ArchFinding[];
  score?: number;
  summary?: Record<string, number>;
}

export type DiagSeverity = 'error' | 'warning' | 'info';

/** A vscode-free description of one diagnostic, keyed by file. */
export interface DiagnosticData {
  path: string;
  /** 1-based line (defaults to 1 when the finding has none). */
  line: number;
  /** 1-based column (defaults to 1 when the finding has none). */
  column: number;
  code: string;
  message: string;
  severity: DiagSeverity;
}

/** Normalizes the CLI severity string to a known [DiagSeverity]. */
export function normalizeSeverity(severity: string): DiagSeverity {
  switch (severity) {
    case 'error':
      return 'error';
    case 'info':
      return 'info';
    case 'warning':
    default:
      return 'warning';
  }
}

/** The user-facing message, with confidence appended when present. */
export function findingMessage(finding: ArchFinding): string {
  return finding.confidence
    ? `${finding.message} (confidence: ${finding.confidence})`
    : finding.message;
}

/** Projects an [ArchFinding] onto vscode-free [DiagnosticData]. */
export function toDiagnosticData(finding: ArchFinding): DiagnosticData {
  return {
    path: finding.path,
    line: finding.line ?? 1,
    column: finding.column ?? 1,
    code: finding.rule,
    message: findingMessage(finding),
    severity: normalizeSeverity(finding.severity),
  };
}

/** Groups findings by their (POSIX) file path, preserving order. */
export function groupByFile(
  findings: ArchFinding[],
): Map<string, DiagnosticData[]> {
  const byFile = new Map<string, DiagnosticData[]>();
  for (const finding of findings) {
    const data = toDiagnosticData(finding);
    const list = byFile.get(data.path) ?? [];
    list.push(data);
    byFile.set(data.path, list);
  }
  return byFile;
}
