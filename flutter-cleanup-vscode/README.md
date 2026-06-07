# Flutter Cleanup (VS Code)

A minimal VS Code extension that runs the [`flutter_cleanup`](../) CLI against the
open workspace and shows its JSON report in an Output Channel.

This is an **MVP**. It proves the integration pipeline only:

> VS Code command → `flutter_cleanup all --json` → parse JSON → Output Channel

There is no Problems-view integration, tree view, code actions, or settings yet —
those come in later iterations.

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
3. Run **Flutter Cleanup: Run All**.

The results appear in **Output → Flutter Cleanup** as a pretty-printed JSON
document:

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
```

Press **F5** in VS Code to launch the Extension Development Host, open a project
that has `flutter_cleanup` on PATH, and run **Flutter Cleanup: Run All**.
