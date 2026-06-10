# Flutter Cleanup (VS Code)

A VS Code extension that runs the [`flutter_cleanup`](../) CLI against the open
workspace. It can dump the raw JSON report into an Output Channel, and — its main
feature — surface **Clean Architecture (ARCH) violations** inline in the Problems
panel:

> Command → `flutter_cleanup architecture --json` → parse → `DiagnosticCollection`

Each violation lands on its exact file and line with its `ARCHnxx` code and a
confidence note, and the architecture **score** is shown in a notification. The
older **Run All** command (raw JSON → Output Channel) is still available.

There are no code actions / quick fixes or settings yet — those come in later
iterations.

## Requirements

- VS Code **1.75** or newer.
- The `flutter_cleanup` CLI installed and available on your `PATH`:

  ```bash
  dart pub global activate flutter_cleanup
  ```

  Ensure the pub global bin directory is on `PATH`:

  - macOS / Linux: `~/.pub-cache/bin`
  - Windows: `%LOCALAPPDATA%\Pub\Cache\bin`

  Verify with:

  ```bash
  flutter_cleanup version
  ```

## Usage

1. Open a Flutter/Dart project folder in VS Code.
2. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`).
3. Run one of:
   - **Flutter Cleanup: Analyze Architecture** — runs `architecture --json` and
     publishes every ARCH violation to the Problems panel (one diagnostic per
     finding, on its file/line, with the `ARCHnxx` code and confidence). A
     notification reports the architecture score and category summary.
   - **Flutter Cleanup: Run All** — runs `all --json` and dumps the raw report to
     the Output Channel.

The **Run All** results appear in **Output → Flutter Cleanup** as a
pretty-printed JSON document:

```json
{
  "schemaVersion": 1,
  "results": [
    { "analyzer": "unused-assets", "findings": [] },
    { "analyzer": "unused-files", "findings": [] },
    { "analyzer": "duplicate-code", "findings": [] },
    { "analyzer": "duplicate-widgets", "findings": [] }
  ]
}
```

### Errors

| Situation | What you see |
| --- | --- |
| No folder open | `No workspace folder is open.` |
| CLI not on PATH | `flutter_cleanup executable not found. Install it and ensure it is available on PATH.` |
| Non-JSON output | `flutter_cleanup returned invalid JSON.` (raw output dumped to the channel) |
| Invalid project | The CLI's `{ "error": { "message": ... } }` document is shown in the channel |

## Development

```bash
npm install
npm run compile      # or: npm run watch
npm test             # compile + mocha unit tests (diagnostic mapping)
```

Press **F5** in VS Code to launch the Extension Development Host, open a project
that has `flutter_cleanup` on PATH, and run **Flutter Cleanup: Analyze
Architecture** (or **Run All**).

The vscode-free diagnostic mapping lives in `src/diagnosticsMapping.ts` and is
covered by `src/test/diagnosticsMapping.test.ts`, so it runs under plain Node
without launching the Extension Host. Full end-to-end tests via
`@vscode/test-electron` are a follow-up.
