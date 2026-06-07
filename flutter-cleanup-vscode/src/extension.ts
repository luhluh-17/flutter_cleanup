import * as vscode from 'vscode';

import { runAll } from './cleanupRunner';

/**
 * Entry point called by VS Code when the extension activates.
 *
 * Registers the single MVP command and ties its lifetime to the extension's
 * subscriptions so VS Code disposes it on deactivation.
 */
export function activate(context: vscode.ExtensionContext): void {
  const disposable = vscode.commands.registerCommand(
    'flutterCleanup.runAll',
    () => runAll(),
  );

  context.subscriptions.push(disposable);
}

export function deactivate(): void {
  // Nothing to clean up: the command is disposed via context.subscriptions and
  // the Output Channel is owned by cleanupRunner.
}
