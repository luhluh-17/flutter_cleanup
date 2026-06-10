import * as vscode from 'vscode';

import { runAll } from './cleanupRunner';
import { analyzeArchitecture } from './architectureDiagnostics';

/**
 * Entry point called by VS Code when the extension activates.
 *
 * Registers the commands and creates the shared architecture
 * `DiagnosticCollection`, tying every disposable to the extension's
 * subscriptions so VS Code cleans them up on deactivation.
 */
export function activate(context: vscode.ExtensionContext): void {
  const diagnostics =
    vscode.languages.createDiagnosticCollection('flutter_cleanup');

  context.subscriptions.push(
    diagnostics,
    vscode.commands.registerCommand('flutterCleanup.runAll', () => runAll()),
    vscode.commands.registerCommand(
      'flutterCleanup.analyzeArchitecture',
      () => analyzeArchitecture(diagnostics),
    ),
  );
}

export function deactivate(): void {
  // Nothing to clean up: commands and the diagnostic collection are disposed
  // via context.subscriptions, and the Output Channel is owned by cleanupRunner.
}
