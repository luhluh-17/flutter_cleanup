# flutter_cleanup

A Dart command-line tool to help Flutter developers identify unused files,
unused assets, dead code, and dependency relationships within a project.

> **Status:** v1 is the CLI foundation. Project-structure validation works
> today; the analyzers (unused assets, dead code, dependencies) are scaffolded
> and will be implemented in future releases.

## Installation

From the project root:

```bash
dart pub get
```

Run via `dart run`, or compile a standalone executable:

```bash
dart compile exe bin/flutter_cleanup.dart -o flutter_cleanup
```

## Usage

```bash
# Validate the structure of the project in the current directory
dart run flutter_cleanup scan

# Validate a project at a specific path
dart run flutter_cleanup scan --path ../my_app

# Find declared assets that are never referenced from lib/**
dart run flutter_cleanup unused-assets
dart run flutter_cleanup unused-assets --path ../my_app

# Find Dart files under lib/ unreachable from lib/main.dart
dart run flutter_cleanup unused-files
dart run flutter_cleanup unused-files --path ../my_app

# Print the version
dart run flutter_cleanup version

# List all commands
dart run flutter_cleanup --help
```

`scan` exits with a non-zero status if the target is not a valid
Flutter/Dart project (missing `pubspec.yaml` or `lib/`).

## Ignoring files (`.flutter_cleanup.yaml`)

To reduce false positives, you can exclude files and directories from analysis.
Create an optional `.flutter_cleanup.yaml` in the **project root**:

```yaml
ignore:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
  - "lib/generated/**"
  - "assets/legacy/**"
```

The same ignore rules apply across `unused-assets`, `unused-files`, and
`duplicate-code`. Ignored paths are never reported, never enter the
import/export graph, and never participate in duplicate comparisons.

> One deliberate exception: for `unused-assets`, ignored Dart files are still
> *read* when looking for asset references. A generated file such as
> `lib/assets.g.dart` that contains `'assets/logo.png'` still counts as a use,
> so the asset is not wrongly flagged. Ignored *assets* are never flagged.

If the file does not exist (or is empty), analysis continues normally with the
built-in defaults — no warning, no error.

### Built-in defaults

These patterns are **always** ignored, even with no config file. User-defined
patterns are added on top of them (they never replace the defaults):

| Pattern | Source |
| --- | --- |
| `**/*.g.dart` | `json_serializable`, `retrofit`, `hive`, … |
| `**/*.freezed.dart` | `freezed` |
| `**/*.mocks.dart` | `mockito` |
| `**/*.gr.dart` | `auto_route` |
| `.flutter-plugins` | Flutter tool output |
| `.flutter-plugins-dependencies` | Flutter tool output |

### Pattern syntax

Matching is powered by [`package:glob`](https://pub.dev/packages/glob) against
**project-relative paths using forward slashes** (e.g. `lib/generated/api.dart`),
on every platform — including Windows. So:

- `*` matches within a single path segment (no `/`).
- `**` matches across segments, so `**/*.g.dart` matches `lib/a/b/foo.g.dart`.
- A trailing `/**` matches everything under a directory at any depth, so
  `lib/generated/**` matches `lib/generated/foo.dart` and
  `lib/generated/sub/deep.dart`.

### Example configurations

Generated code only (most projects):

```yaml
ignore:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
```

Build output and tooling artifacts:

```yaml
ignore:
  - "build/**"
  - ".dart_tool/**"
```

Legacy assets kept for reference but excluded from analysis:

```yaml
ignore:
  - "assets/legacy/**"
  - "lib/generated/**"
```

### `unused-assets` (v1)

Reads directory-style entries under `flutter > assets` in `pubspec.yaml`,
recursively collects the files in those directories, then reports any whose
project-relative path never appears as a string literal in `lib/**`.

**Known limitations (v1):**

- Only directory-style entries (e.g. `assets/images/`) are analyzed;
  single-file entries (`assets/images/logo.png`) are ignored.
- Matching is string/RegExp based (no AST). Dynamic references such as
  `Image.asset(variable)` or built-up/interpolated paths are not resolved, so
  the asset may be reported as unused.
- Any string literal equal to the asset path counts as a use — even one inside
  a comment-like string. This is the safe direction: it avoids flagging a
  used asset for deletion, at the cost of occasionally missing a truly unused
  one.
- Only `lib/**` is scanned for references (not `test/`, `bin/`, etc.).

### `unused-files` (v1)

Builds an import/export/part graph of the Dart files under `lib/` (parsing
directives, no AST), treats `lib/main.dart` as the single reachability root,
and reports every `lib/**/*.dart` file not reachable from it.

**Known limitations (v1):**

- Single entrypoint: only `lib/main.dart` is a root. Files reachable only from
  `bin/`, `test/`, or other app entrypoints are reported as unused.
- No AST: directives are matched by RegExp at line start. Conditional-import
  alternatives (`import 'a' if (...) 'b';`) and directive-like text in
  comments/strings may be mis-handled.
- No awareness of reflection, code generation, or routing
  (GoRouter / AutoRoute / Riverpod). Files referenced only by such mechanisms
  may be flagged.
- Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*.gr.dart`)
  are ignored by default (see
  [Ignoring files](#ignoring-files-flutter_cleanupyaml)). Add a
  `.flutter_cleanup.yaml` `ignore:` entry to exclude others.
- When `lib/main.dart` is absent, no analysis is performed (reachability is
  undefined).

## Architecture

The CLI is built on `package:args` `CommandRunner` with a layered structure
designed so new analyzers can be added without touching the CLI core:

```
bin/flutter_cleanup.dart   Thin entry point -> CliRunner
lib/src/
  cli/                     CommandRunner setup and command registration
  commands/                One Command per CLI command + base + ReportPrinter
  analysis/                Analyzer interface + AnalysisResult (extension seam)
  models/                  ProjectPaths, ValidationResult, Finding, OutputFormat
  services/                ProjectValidator, Logger (ANSI output), IgnoreService
  version.dart             Single source of truth for the version
```

Project-scoped commands extend `FlutterCleanupCommand`
([base_command.dart](lib/src/commands/base_command.dart)), which supplies the
shared `--path` option and an `outputFormat` hook. Output goes through
`ReportPrinter`, which is format-aware (`text` today, `json` reserved) so a
`--json` flag can be added later without reworking the output layer.

### Command roadmap

`scan`, `version`, and `unused-assets` exist today. The architecture is ready
for `unused-files`, `graph`, and `doctor` to be added the same way — no core
changes needed.

### Adding a command

1. Create a class extending `FlutterCleanupCommand` (or `Command<int>` for
   commands that don't target a project) in `lib/src/commands/`.
2. Register it in `lib/src/cli/cli_runner.dart`.

### Adding an analyzer

Implement the `Analyzer` interface in `lib/src/analysis/`, return
`AnalysisResult`s built from `Finding`s, and invoke it from the relevant
command.
