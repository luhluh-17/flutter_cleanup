import * as vscode from 'vscode';
import execa from 'execa';

/**
 * The shared "Flutter Cleanup" Output Channel.
 *
 * Created lazily and reused across runs so repeated invocations write to a
 * single, stable channel rather than spawning a new one each time.
 */
let channel: vscode.OutputChannel | undefined;

function getChannel(): vscode.OutputChannel {
  return (channel ??= vscode.window.createOutputChannel('Flutter Cleanup'));
}

/**
 * Invokes the `flutter_cleanup` CLI with the given arguments.
 *
 * Extracted so future per-analyzer commands (Duplicate Widgets, Unused Files, …)
 * can reuse the exact same execution path — only the args differ.
 */
function runFlutterCleanup(args: string[], cwd: string) {
  return execa('flutter_cleanup', args, { cwd });
}

/** Clears the channel, writes the pretty-printed JSON, and focuses it. */
function renderJson(output: vscode.OutputChannel, parsed: unknown): void {
  output.clear();
  output.appendLine(JSON.stringify(parsed, null, 2));
  output.show(true);
}

/**
 * Whether an execa error means the `flutter_cleanup` binary could not be found.
 *
 * POSIX shells surface this as `ENOENT`. On Windows, cross-spawn routes the
 * command through `cmd.exe`, which instead exits 1 with a "not recognized"
 * message on stderr — so both cases must be detected.
 */
function isExecutableNotFound(err: any): boolean {
  if (err?.code === 'ENOENT') {
    return true;
  }
  const stderr = typeof err?.stderr === 'string' ? err.stderr : '';
  return (
    /is not recognized as an internal or external command/i.test(stderr) ||
    /command not found/i.test(stderr)
  );
}

/**
 * Command handler for `flutterCleanup.runAll`.
 *
 * Runs `flutter_cleanup all --json` against the open workspace and renders the
 * parsed JSON into the Output Channel. This is the whole MVP pipeline:
 * VS Code command -> CLI -> JSON -> Output Channel.
 */
export async function runAll(): Promise<void> {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    vscode.window.showErrorMessage('No workspace folder is open.');
    return;
  }

  const output = getChannel();

  try {
    const { stdout } = await runFlutterCleanup(
      ['all', '--json'],
      folder.uri.fsPath,
    );

    try {
      renderJson(output, JSON.parse(stdout));
    } catch {
      // The process succeeded but produced something that is not JSON. Dump the
      // raw output so the user can see what came back.
      output.clear();
      output.appendLine(stdout);
      output.show(true);
      vscode.window.showErrorMessage('flutter_cleanup returned invalid JSON.');
    }
  } catch (err: any) {
    // A non-zero exit (e.g. an invalid project) makes execa throw, but the CLI
    // still emits a valid `{ error: { message } }` document on stdout. Surface
    // that JSON before falling back to generic error handling.
    if (typeof err?.stdout === 'string' && err.stdout.trim()) {
      try {
        renderJson(output, JSON.parse(err.stdout));
        return;
      } catch {
        // Not JSON — fall through to the generic handlers below.
      }
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
  }
}
