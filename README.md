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

# Detect Clean Architecture / Riverpod violations (ARCH101–503) under lib/
dart run flutter_cleanup architecture
dart run flutter_cleanup architecture --path ../my_app
dart run flutter_cleanup architecture --report   # also print the dependency tree

# Flag maintainability smells (large files, long methods/build(), deep nesting)
dart run flutter_cleanup maintainability
dart run flutter_cleanup maintainability --path ../my_app

# Find classes that are safe to migrate to a Dart 3.12+ primary constructor
dart run flutter_cleanup primary-constructors
dart run flutter_cleanup primary-constructors --path ../my_app

# Run every analyzer above in a single pass
dart run flutter_cleanup all
dart run flutter_cleanup all --path ../my_app

# Emit machine-readable JSON instead of text (works on every analyzer + `all`)
dart run flutter_cleanup duplicate-widgets --json
dart run flutter_cleanup all --json --path ../my_app

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
`duplicate-code`, `duplicate-widgets`, `maintainability`, and
`primary-constructors` (and therefore `all`). Ignored paths are never reported,
never enter the import/export graph, and never participate in duplicate
comparisons.

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

### `architecture`

Detects **Clean Architecture + Feature-Based + Riverpod** violations across
`lib/`, building an import/dependency graph from the Dart AST and checking it
against a categorized rule set (ARCH101–503). Each finding carries a file, line,
and a **confidence** (`high`/`medium`/`low`); the command also reports an
**architecture score** (0–100) and, with `--report`, the feature-dependency tree.

```bash
dart run flutter_cleanup architecture --path ../my_app
dart run flutter_cleanup architecture --json        # score + summary + findings
dart run flutter_cleanup architecture --report      # + feature dependency tree
```

**Rule categories** (the hundreds digit groups them; score weight in parentheses):

| Range | Category (weight) | Examples |
| --- | --- | --- |
| ARCH1xx | Layer dependency & purity (3) | domain imports Dio (101), entity imports model (102), presentation imports datasource (103), illegal layer direction (106), page instantiates repository (110) |
| ARCH2xx | Structure & placement (2) | data layer without a backing domain layer (202), use case / model / entity in the wrong folder (204–208), repo impl with no contract (209) |
| ARCH3xx | Riverpod (2) | notifier constructs its own dependency instead of injecting it (301) |
| ARCH4xx | Routing (2) | routing outside `lib/routing` (401), feature defines its own `GoRouter` (402), stray route file (403) |
| ARCH5xx | Feature boundaries (5) | cross-feature import (501), circular feature dependency (502), god-feature fan-out (503) |

**Recognized layers.** Each feature is organized into four layers —
`presentation/` (`pages`/`providers`/`widgets`/`controllers`/`dialogs`/`painters`/`styles`),
`application/` (`services`/`coordinators`/`facades`/`runtime`),
`domain/` (`entities`/`repositories`/`usecases`/`value_objects`/`services`), and
`data/` (`datasources`/`data_sources`/`models`/`mappers`/`dto`/`repositories`).
Shared infrastructure lives at the top level in `lib/core/`, `lib/shared/`,
`lib/initialization/`, and `lib/routing/` (the blessed home for route
definitions). Dependencies flow inward toward `domain`: presentation may use
application and domain; application and data may use domain; domain depends on
nothing outward. A feature need **not** be a full vertical slice: it may be
UI-only (its domain/data shared in `core/`), logic-only, or a headless service
with no presentation. Because every layer points inward at `domain`, the only
incompleteness that is actually broken — and the only one flagged (ARCH202) — is
a `data/` layer with no `domain/` layer to back it. `presentation`, `data`, and
`application` are all optional.

**Feature groups (nested features).** Features may be grouped one level deep: a
directory under `lib/features/` that holds no layer folders directly but whose
children are themselves features (e.g.
`features/workflows/dashboard/{data,domain,presentation}/…`) is a *group*, and
each child is a sub-feature identified as `"<group>/<sub>"`. Completeness,
placement, and cross-feature rules address the real sub-features, not the empty
group container — so a group is never mis-reported as an unrecognized folder or
as a feature missing all its layers. Flat features are unchanged: a layer folder
at the first level always wins, so `features/auth/data/…` stays the flat feature
`auth`.

**Extending the vocabulary.** The folder vocabulary is strict by design (so stray
folders can't silently escape the layer rules), but real projects grow folders
the canonical layout doesn't name. Rather than fork the tool, *add* to the
vocabulary from `.flutter_cleanup.yaml`:

```yaml
architecture:
  sublayers:
    presentation: [effects]  # extra presentation/ sub-folders
    data: [adapters]         # extra data/ sub-folders
  top_level: [config]        # extra lib/<dir> folders beyond core/features/shared/…
```

Entries are **added** to the built-ins, never replace them, and only suppress the
structure warnings (ARCH210–212) for the named folders — the layer/purity rules
still apply. Parsing is tolerant: a missing section, wrong types, or unknown keys
are ignored.

#### Maintainability thresholds

The `maintainability` analyzer's thresholds are tunable from the same
`.flutter_cleanup.yaml`. Every value defaults to the table in
[`maintainability`](#maintainability); override only what you need (a partial
`{ warning: … }` keeps the matching default `error`):

```yaml
maintainability:
  enabled: true                              # set false to skip the analyzer
  file_lines:           { warning: 500,  error: 1000 }
  method_lines:         { warning: 50,   error: 100 }
  build_method_lines:   { warning: 100,  error: 200 }
  widget_count:         { warning: 10,   error: 20 }
  widget_nesting_depth: { warning: 6,    error: 10 }
```

Parsing is tolerant (mirrors the rest of the config): a missing section,
malformed YAML, or wrong-typed values fall back to the defaults. The analyzer
also skips generated files by suffix (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
`*.config.dart`, `*.mocks.dart`, `*.pb.dart`, `*.pbenum.dart`, `*.pbjson.dart`,
`*.pbserver.dart`) in addition to your `ignore:` patterns.

The **score** starts at 100 and subtracts each violation's category weight
(feature-boundary problems cost the most), floored at 0.

**Analysis mode — `syntactic-ast` (no type resolution).** Rules walk the parsed
AST without an element model, so a few are inherently heuristic and reported at
`medium` confidence (e.g. 209 can't see typedef aliases or generic bases; 301 only
flags literal dependency construction; 403 keys on filename). This trade-off is
surfaced as `"analysisMode": "syntactic-ast"` in the JSON.

### `maintainability`

Flags **maintainability smells** in non-generated Dart files under `lib/` —
files, methods, and widget trees that have grown large enough to be worth
refactoring. Each file is parsed once with the `analyzer` package and all five
rules run over that single AST, so the command scales to large projects.

```bash
dart run flutter_cleanup maintainability --path ../my_app
```

**Rules** (each compared against a configurable warning/error threshold):

| Rule | Measures | Default warning / error |
| --- | --- | --- |
| File length | Lines of code in the file (comment-only and blank lines excluded) | 500 / 1000 |
| Method length | Source lines of each function/method (getters, setters, constructors, and `build` excluded) | 50 / 100 |
| `build()` length | Body length of a `Widget build(BuildContext)` method | 100 / 200 |
| Widget count | Widget classes declared in one file (`StatelessWidget`, `StatefulWidget`, `ConsumerWidget`, `HookWidget`, `HookConsumerWidget`, `ConsumerStatefulWidget`) | 10 / 20 |
| Widget nesting depth | Deepest widget-tree nesting inside a `build()` body | 6 / 10 |

A measured value at or above the **error** threshold is reported at `error`
severity, at or above **warning** as `warning`, and below warning produces no
finding. Each finding shows the accepted `warning–error` limit range and carries
an actionable recommendation. An **Accepted standards** legend of the active
thresholds is printed above the findings on every text-mode run:

```text
Accepted standards (warning / error)
────────────────────────────────────
  File length      500 / 1000 lines
  Method length     50 / 100 lines
  build() length   100 / 200 lines
  Widget count      10 / 20 classes
  Nesting depth      6 / 10 levels

Maintainability
───────────────
! lib/features/home/home_page.dart — File contains 742 lines (limit: 500–1000).
    ↳ Split into smaller widgets or feature-specific files.
! lib/features/home/home_page.dart:88 — build() method contains 156 lines (limit: 100–200).
    ↳ Extract reusable widgets.
! lib/dashboard/dashboard_page.dart — File contains 14 widget classes (limit: 10–20).
    ↳ Move widgets into separate files.
```

**Configuration.** Thresholds are tunable (and the analyzer can be disabled
entirely) from `.flutter_cleanup.yaml` — see
[Maintainability thresholds](#maintainability-thresholds).

**Known limitations:**

- **Syntactic AST, no type resolution.** Widget classes are recognized by their
  `extends` clause and widget nesting is a practical AST approximation: nesting
  counts *widget* constructor expressions (`InstanceCreationExpression` and
  PascalCase calls), skipping value types via a small blocklist (`EdgeInsets`,
  `Color`, …). Depth is read from `build()` bodies only.
- **Line counts are source-based**, not logical statements; a long multi-line
  expression counts as the lines it spans.
- **`build()` is matched by name + a single `BuildContext` parameter**, detected
  from source text rather than a resolved type.

### `primary-constructors`

Identifies classes under `lib/` that are **safe candidates** for migration to a
Dart 3.12+ [primary constructor](https://codewithandrea.com/articles/safely-migrate-primary-constructors/)
— the syntax that folds field declaration and constructor parameters into the
class header, removing the classic widget boilerplate:

```dart
// before                                    // after (Dart 3.12+)
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({                       class PrimaryButton({
    super.key,                                  super.key,
    required this.label,                        required final String label,
  });                                         }) extends StatelessWidget {
  final String label;
  ...                                           ...
}                                             }
```

```bash
dart run flutter_cleanup primary-constructors --path ../my_app
dart run flutter_cleanup primary-constructors --json
```

Migrating is **not always safe** — a field doc-comment can silently drop
`required`, a constructor body that initializes a field can't be folded, an
untyped field breaks, a named `super(...)` call can't be reproduced, and so on.
This command therefore reports only the **provably safe** subset: a
high-precision "ready to migrate" signal, not a lint of blockers. Each candidate
is emitted as an `info` finding.

**A class is reported only when all of the following hold** (each rule maps to
one of the article's "unsafe situations"):

- It declares **exactly one constructor**, and that constructor is **unnamed**,
  **generative** (no `factory`), has **no initializer list** (rules out named
  `super(...)` calls and `: field = x`), and has **no body or an empty body**.
- **Every constructor parameter** is a field formal (`this.x`) or super formal
  (`super.x`), and there is **at least one `this.` field formal** (otherwise
  there is no boilerplate to remove).
- **Every field bound by a `this.` formal** is `final`, **explicitly typed**,
  **uninitialized**, not `late`/`static`, carries **no annotation**, and has
  **no documentation comment** (which could otherwise swallow `required`).

Anything failing a check is silently skipped rather than reported.

```text
Primary constructors
────────────────────
• lib/widgets/primary_button.dart:3 — Class "PrimaryButton" is a safe candidate for primary-constructor migration.
    ↳ Convert to a Dart 3.12+ primary constructor to remove field/constructor boilerplate.

! 1 migration candidate found.
```

**Known limitations:**

- **Syntactic AST, no type resolution.** Everything above is a source-level
  check; the tool never confirms the class actually compiles, and it does not
  perform the migration (it only surfaces candidates).
- **Conservative by design.** Because it skips anything questionable, some
  genuinely-migratable classes (e.g. those with an inherited field formal, or a
  benign non-field parameter) are not reported.
- Generated files are skipped by suffix (same list as `maintainability`) in
  addition to your `ignore:` patterns.

### `all`

Runs every analyzer (`unused-assets`, `unused-files`, `duplicate-code`,
`duplicate-widgets`, `maintainability`, `primary-constructors`, `architecture`)
in a single pass. The project is validated once, then each analyzer's findings
are printed under its own heading.

```bash
dart run flutter_cleanup all --path ../my_app
```

Like the individual commands, it exits non-zero only when validation fails
(missing `pubspec.yaml` or `lib/`); findings themselves do not change the exit
code. When `lib/main.dart` is absent, the `unused-files` section is skipped (its
reachability root is undefined) while the other analyzers still run.

The section order is `unused-assets`, `unused-files`, `duplicate-code`,
`duplicate-widgets`, `maintainability`, `primary-constructors`, `architecture`.

## JSON output (`--json`)

Every analyzer command — and `all` — accepts `--json`, which replaces the
human-readable text report with a single, pretty-printed JSON document on
stdout. JSON mode emits **no banners, ANSI colors, or decorative separators**,
so the output can be piped straight into a parser. This is the machine-readable
contract that integrations (CI/CD, the VS Code extension, dashboards, and other
automation) build on.

Exit semantics are unchanged: a successful analysis exits `0` regardless of how
many findings it produced, and a validation failure exits `1`. Consumers should
therefore inspect the JSON (not the exit code) to count findings; a non-zero
exit means a validation or usage error, with the reason in the `error` object.

Every document carries a top-level `"schemaVersion"` so consumers can evolve
safely as fields are added later.

### Single-analyzer schema

`unused-assets`, `unused-files`, `duplicate-code`, `duplicate-widgets`,
`maintainability`, and `primary-constructors` each emit one analyzer document:

```json
{
  "schemaVersion": 1,
  "analyzer": "duplicate-widgets",
  "findings": [
    {
      "rule": "duplicate_widget",
      "path": "lib/widgets/login_card.dart",
      "severity": "info",
      "message": "Widget \"LoginCard\" is highly similar to \"RegisterCard\" in lib/widgets/register_card.dart (96% similarity, 24 nodes)."
    }
  ]
}
```

Each finding has a stable shape:

| Field | Type | Notes |
| --- | --- | --- |
| `rule` | string | Analyzer-specific rule id (e.g. `duplicate_widget`, `ARCH101`). |
| `path` | string | Project-relative path, forward-slashed. |
| `severity` | string | One of `info`, `warning`, `error`. |
| `message` | string | Human-readable description. |
| `line` | int? | 1-based line. Optional — emitted by `architecture` and `maintainability` (method/`build()`/nesting findings); omitted otherwise. |
| `column` | int? | 1-based column. Optional. |
| `confidence` | string? | `high`/`medium`/`low`. Optional — emitted by `architecture`. |
| `recommendation` | string? | Actionable fix suggestion. Optional — emitted by `maintainability` (and any rule that has one). |

Optional fields are omitted entirely when unset, so analyzers that work at file
granularity produce the same document shape as before.

A run with no findings emits `"findings": []`. When `lib/main.dart` is absent,
`unused-files` still emits a well-formed empty result rather than special output,
so consumers need no analyzer-specific handling.

### Aggregate schema (`all`)

`all --json` emits one document wrapping each analyzer's result in order. The
nested results use the same shape as above but omit their own `schemaVersion`
(it is a document-level field):

```json
{
  "schemaVersion": 1,
  "results": [
    { "analyzer": "unused-assets", "findings": [] },
    { "analyzer": "unused-files", "findings": [] },
    { "analyzer": "duplicate-code", "findings": [] },
    { "analyzer": "duplicate-widgets", "findings": [] },
    { "analyzer": "maintainability", "findings": [] },
    { "analyzer": "primary-constructors", "findings": [] },
    {
      "analyzer": "architecture",
      "findings": [],
      "analysisMode": "syntactic-ast",
      "score": 100,
      "summary": { "layer": 0, "structure": 0, "riverpod": 0, "routing": 0, "feature": 0 },
      "violationsByCode": {},
      "dependencies": {}
    }
  ]
}
```

The `architecture` result adds `analysisMode`, `score`, `summary`,
`violationsByCode`, and `dependencies` keys alongside the standard
`analyzer`/`findings`.

### Validation failure

When the target is not a valid Flutter/Dart project, `--json` emits a structured
error (and exits `1`) instead of empty output:

```json
{
  "schemaVersion": 1,
  "error": {
    "message": "pubspec.yaml not found"
  }
}
```

### Intended consumers

- **CI/CD** — gate a build on findings by parsing the JSON (e.g. fail when any
  analyzer's `findings` is non-empty), independent of the process exit code.
- **VS Code extension** — surface findings inline by reading each finding's
  `path`, `severity`, and `message`.
- **Dashboards / automation** — aggregate `all --json` across projects over time.

## Architecture

The CLI is built on `package:args` `CommandRunner` with a layered structure
designed so new analyzers can be added without touching the CLI core:

```
bin/flutter_cleanup.dart   Thin entry point -> CliRunner
lib/src/
  cli/                     CommandRunner setup and command registration
  commands/                One Command per CLI command + base + ReportPrinter
  analysis/                Analyzer interface + AnalysisResult (extension seam)
  analyzers/               unused-assets/files, duplicate-code/widgets,
                           maintainability/ (config, issue model, nesting util),
                           primary-constructors/
  architecture/            ARCH rule engine: definition (ArchitectureDefinition,
                           Layer), layer classifier, import resolver, dependency
                           graph, parse-once context, rules/, scoring analyzer
  models/                  ProjectPaths, ValidationResult, Finding, OutputFormat
  services/                ProjectValidator, Logger (ANSI output), IgnoreService
  version.dart             Single source of truth for the version
```

The `architecture/` engine is layered for extension: an `ArchitectureDefinition`
abstracts the architecture style (Clean Architecture is the only implementation
today, but the layer-direction matrix and forbidden-package set are pluggable),
and rules implement a small `ArchitectureRule` interface assembled by
`cleanArchitectureRules()`. Rules emit a rich `ArchitectureViolation` (with
feature/layer/cycle metadata) that is projected onto the lean `Finding` for
output — keeping room for a future dashboard or graph view without bloating
`Finding`.

Project-scoped commands extend `FlutterCleanupCommand`
([base_command.dart](lib/src/commands/base_command.dart)), which supplies the
shared `--path` option and the `--json` flag (exposed as an `outputFormat` hook).
Output goes through `ReportPrinter`, which is format-aware (`text` and `json`),
so commands pass their `OutputFormat` through without knowing how either format
is rendered. See [JSON output](#json-output---json).

### Command roadmap

`scan`, `version`, `unused-assets`, `unused-files`, `duplicate-code`,
`duplicate-widgets`, `architecture`, `maintainability`, `primary-constructors`,
and `all` exist today. The architecture is ready for `graph` and `doctor` to be
added the same way — no core changes needed.

### Adding a command

1. Create a class extending `FlutterCleanupCommand` (or `Command<int>` for
   commands that don't target a project) in `lib/src/commands/`.
2. Register it in `lib/src/cli/cli_runner.dart`.

### Adding an analyzer

Implement the `Analyzer` interface in `lib/src/analysis/`, return
`AnalysisResult`s built from `Finding`s, and invoke it from the relevant
command.
