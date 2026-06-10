import * as vscode from 'vscode';
import * as path from 'path';

import { runFlutterCleanup, isExecutableNotFound } from './cli';
import {
  ArchitectureResultJson,
  DiagnosticData,
  DiagSeverity,
  groupByFile,
} from './diagnosticsMapping';

/** The diagnostic source label shown next to each problem. */
const SOURCE = 'flutter_cleanup';

const SEVERITY: Record<DiagSeverity, vscode.DiagnosticSeverity> = {
  error: vscode.DiagnosticSeverity.Error,
  warning: vscode.DiagnosticSeverity.Warning,
  info: vscode.DiagnosticSeverity.Information,
};

/** Builds a `vscode.Diagnostic` from vscode-free [DiagnosticData]. */
function toDiagnostic(data: DiagnosticData): vscode.Diagnostic {
  const line = Math.max(0, data.line - 1);
  const column = Math.max(0, data.column - 1);
  const range = new vscode.Range(line, column, line, Number.MAX_SAFE_INTEGER);
  const diagnostic = new vscode.Diagnostic(
    range,
    data.message,
    SEVERITY[data.severity],
  );
  diagnostic.code = data.code;
  diagnostic.source = SOURCE;
  return diagnostic;
}

/**
 * Command handler for `flutterCleanup.analyzeArchitecture`.
 *
 * Runs `flutter_cleanup architecture --json` against the open workspace, maps
 * the findings into the shared [collection] (clear-and-repopulate), and reports
 * the architecture score. This is the whole pipeline: command → CLI → JSON →
 * Problems panel.
 */
export async function analyzeArchitecture(
  collection: vscode.DiagnosticCollection,
): Promise<void> {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    vscode.window.showErrorMessage('No workspace folder is open.');
    return;
  }
  const root = folder.uri.fsPath;

  let stdout: string;
  try {
    ({ stdout } = await runFlutterCleanup(['architecture', '--json'], root));
  } catch (err: any) {
    // A non-zero exit (e.g. an invalid project) still emits a JSON document on
    // stdout; surface its error message before the generic handlers.
    const errorMessage = readErrorJson(err?.stdout);
    if (errorMessage) {
      vscode.window.showErrorMessage(`flutter_cleanup: ${errorMessage}`);
      return;
    }
    if (isExecutableNotFound(err)) {
      vscode.window.showErrorMessage(
        'flutter_cleanup executable not found. ' +
          'Install it and ensure it is available on PATH.',
      );
      return;
    }
    vscode.window.showErrorMessage(
      err?.shortMessage ?? err?.message ?? String(err),
    );
    return;
  }

  let result: ArchitectureResultJson;
  try {
    result = JSON.parse(stdout) as ArchitectureResultJson;
  } catch {
    vscode.window.showErrorMessage('flutter_cleanup returned invalid JSON.');
    return;
  }

  publish(collection, root, result);
}

/** Clears and repopulates [collection] from the analyzer [result]. */
function publish(
  collection: vscode.DiagnosticCollection,
  root: string,
  result: ArchitectureResultJson,
): void {
  collection.clear();
  const findings = result.findings ?? [];
  const byFile = groupByFile(findings);

  for (const [relPath, dataList] of byFile) {
    const uri = vscode.Uri.file(path.join(root, ...relPath.split('/')));
    collection.set(uri, dataList.map(toDiagnostic));
  }

  const score = result.score;
  if (typeof score === 'number') {
    const summary = formatSummary(result.summary);
    const message =
      findings.length === 0
        ? `Architecture score: ${score}/100 — no violations 🎉`
        : `Architecture score: ${score}/100 — ${findings.length} violation(s)${summary}`;
    vscode.window.showInformationMessage(message);
  }
}

/** ` (layer: 2, feature: 1)` for the non-zero categories, or ''. */
function formatSummary(summary?: Record<string, number>): string {
  if (!summary) {
    return '';
  }
  const parts = Object.entries(summary)
    .filter(([, count]) => count > 0)
    .map(([category, count]) => `${category}: ${count}`);
  return parts.length ? ` (${parts.join(', ')})` : '';
}

/** Extracts `error.message` from a CLI error JSON document, if present. */
function readErrorJson(stdout: unknown): string | undefined {
  if (typeof stdout !== 'string' || !stdout.trim()) {
    return undefined;
  }
  try {
    const parsed = JSON.parse(stdout);
    const message = parsed?.error?.message;
    return typeof message === 'string' ? message : undefined;
  } catch {
    return undefined;
  }
}
