import execa from 'execa';

/**
 * Invokes the `flutter_cleanup` CLI with the given arguments in [cwd].
 *
 * Shared by every command (Run All, Analyze Architecture, …) so the single
 * execution path — and its cross-platform quirks — lives in one place.
 */
export function runFlutterCleanup(args: string[], cwd: string) {
  return execa('flutter_cleanup', args, { cwd });
}

/**
 * Whether an execa error means the `flutter_cleanup` binary could not be found.
 *
 * POSIX shells surface this as `ENOENT`. On Windows, cross-spawn routes the
 * command through `cmd.exe`, which instead exits 1 with a "not recognized"
 * message on stderr — so both cases must be detected.
 */
export function isExecutableNotFound(err: any): boolean {
  if (err?.code === 'ENOENT') {
    return true;
  }
  const stderr = typeof err?.stderr === 'string' ? err.stderr : '';
  return (
    /is not recognized as an internal or external command/i.test(stderr) ||
    /command not found/i.test(stderr)
  );
}
