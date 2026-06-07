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

# Find highly similar (likely copy-pasted) Dart files under lib/
dart run flutter_cleanup duplicate-code
dart run flutter_cleanup duplicate-code --path ../my_app

# Find structurally highly similar Flutter widgets under lib/
dart run flutter_cleanup duplicate-widgets
dart run flutter_cleanup duplicate-widgets --path ../my_app

# Run every analyzer above in a single pass
dart run flutter_cleanup all
dart run flutter_cleanup all --path ../my_app

# Print the version
dart run flutter_cleanup version

# List all commands
dart run flutter_cleanup --help
```

`scan` exits with a non-zero status if the target is not a valid
Flutter/Dart project (missing `pubspec.yaml` or `lib/`).

### Passing Windows paths

PowerShell accepts back-slashed Windows paths unquoted:

```powershell
dart run flutter_cleanup scan --path C:\Users\you\my_app
```

In a **bash-style shell** (Git Bash, WSL), an unquoted `\` is an escape
character, so `C:\Users\you\my_app` arrives as `C:Usersyoumy_app` with the
separators stripped. Quote the path or use forward slashes instead:

```bash
dart run flutter_cleanup scan --path "C:/Users/you/my_app"
```

If a path is passed in the mangled form, the tool now stops with a clear error
(rather than silently resolving it against the current directory).

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

The same ignore rules apply across `unused-assets`, `unused-files`,
`duplicate-code`, and `duplicate-widgets` (and therefore `all`). Ignored paths
are never reported, never enter the import/export graph, and never participate in
duplicate comparisons.

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
| `**/*.pb.dart` | protobuf / gRPC (`protoc-gen-dart`) |
| `**/*.pbgrpc.dart` | protobuf / gRPC (`protoc-gen-dart`) |
| `**/*.pbjson.dart` | protobuf / gRPC (`protoc-gen-dart`) |
| `**/*.pbenum.dart` | protobuf / gRPC (`protoc-gen-dart`) |
| `.flutter-plugins` | Flutter tool output |
| `.flutter-plugins-dependencies` | Flutter tool output |

#### Generated protobuf artifacts

`protoc-gen-dart` emits a fixed set of files for every `.proto`, regardless of
whether anything imports them:

```text
activity.pb.dart        // message classes
activity.pbgrpc.dart    // gRPC service stubs
activity.pbjson.dart    // JSON/reflection descriptors
activity.pbenum.dart    // enum stubs (emitted even when there are no enums)
```

The `*.pbjson.dart` and `*.pbenum.dart` files in particular are descriptors and
stubs that are intentionally never imported, so `unused-files` would otherwise
flag them en masse — even though the underlying `.proto` definitions and gRPC
services are all in active use. They are generated implementation artifacts, not
meaningful cleanup targets, so they are ignored by default.

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
- Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*.gr.dart`,
  and the protobuf set `*.pb.dart` / `*.pbgrpc.dart` / `*.pbjson.dart` /
  `*.pbenum.dart`) are ignored by default (see
  [Ignoring files](#ignoring-files-flutter_cleanupyaml)). Add a
  `.flutter_cleanup.yaml` `ignore:` entry to exclude others.
- When `lib/main.dart` is absent, no analysis is performed (reachability is
  undefined).

### `duplicate-widgets`

Finds Flutter widgets whose **widget-tree structure** is highly similar — likely
copy-pasted UI. This is a different signal from `duplicate-code`: that command
compares whole *files* as normalized token streams, while this one compares the
*structure* of each widget recovered from the Dart AST.

```bash
dart run flutter_cleanup duplicate-widgets --path ../my_app
```

**How it works:**

- **Discovery.** Walks `lib/**/*.dart` (honoring `.flutter_cleanup.yaml` and the
  built-in default ignores), parsing each file with the `analyzer` package. It
  collects every `StatelessWidget` and `State` subclass that has a `build()`
  method. A `StatefulWidget`'s tree is read from its companion `State` class;
  the widget name is recovered from `extends State<Foo>`.
- **Structural fingerprint.** Each `build()` body is reduced to the pre-order
  sequence of *widget constructor names* (`Card`, `Column`, `Text`,
  `ElevatedButton`, …). Strings, numbers, identifiers, and callback bodies are
  ignored — only structure remains. A small blocklist drops non-widget value
  types (`EdgeInsets`, `Color`, `TextStyle`, …).
- **Similarity.** Fingerprints are compared with **Jaccard similarity over
  size-2 shingles** (adjacent widget pairs), the same scoring approach as
  `duplicate-code`. Pairs scoring at or above the **similarity threshold
  (`0.85`)** are reported, one `Finding` per pair.
- **Minimum widget size.** Widgets with fewer than **`minWidgetNodes` (`8`)**
  fingerprint nodes are ignored. Tiny widgets (`Text(...)`,
  `Container(child: Text(...))`) look alike to almost everything and would only
  add noise.

Each finding includes the node count, which is useful when tuning the threshold:

```text
Duplicate Widgets
─────────────────
lib/login_card.dart — Widget "LoginCard" is highly similar to "RegisterCard" in lib/register_card.dart (96% similarity, 24 nodes).

! 1 duplicate widget pair found.
```

**Known limitations:**

- **Helper methods are not analyzed.** Only the `build()` body is walked; widgets
  extracted into helpers (`Widget _buildHeader() => …`) are invisible and are not
  inlined.
- **Widget trees are extracted only from `build()`** — not from other methods or
  top-level widget-returning functions.
- **No element resolution.** Parsing is syntactic: a PascalCase identifier in
  call position is *assumed* to be a widget/value constructor (mitigated by the
  small value-type blocklist).
- **No framework awareness** — Riverpod, GoRouter, and code-generation patterns
  are not understood.
- **O(n²) pairwise comparison.** Fine for typical projects; not tuned for very
  large monorepos.

### `all`

Runs every analyzer (`unused-assets`, `unused-files`, `duplicate-code`,
`duplicate-widgets`) in a single pass. The project is validated once, then each
analyzer's findings are printed under its own heading.

```bash
dart run flutter_cleanup all --path ../my_app
```

Like the individual commands, it exits non-zero only when validation fails
(missing `pubspec.yaml` or `lib/`); findings themselves do not change the exit
code. When `lib/main.dart` is absent, the `unused-files` section is skipped (its
reachability root is undefined) while the other analyzers still run.

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

`scan`, `version`, `unused-assets`, `unused-files`, `duplicate-code`,
`duplicate-widgets`, and `all` exist today. The architecture is ready for
`graph` and `doctor` to be added the same way — no core changes needed.

### Adding a command

1. Create a class extending `FlutterCleanupCommand` (or `Command<int>` for
   commands that don't target a project) in `lib/src/commands/`.
2. Register it in `lib/src/cli/cli_runner.dart`.

### Adding an analyzer

Implement the `Analyzer` interface in `lib/src/analysis/`, return
`AnalysisResult`s built from `Finding`s, and invoke it from the relevant
command.
