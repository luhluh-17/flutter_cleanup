## Unreleased

- `architecture`: support **feature groups** — one level of feature nesting under
  `lib/features/`. A directory that holds no layer folders directly but whose
  children do (e.g. `features/workflows/dashboard/{data,domain,presentation}/…`)
  is treated as a group, and each child is a sub-feature identified as
  `"<group>/<sub>"`. The group container is no longer mis-flagged as an
  unrecognized folder (ARCH210) or as a feature missing all its layers
  (ARCH201–203); completeness, placement, and cross-feature rules now address the
  real sub-features instead. Flat features are unchanged: a layer folder at the
  first level still wins, so `features/auth/data/…` stays the flat feature
  `auth`.
- `architecture`: recognize a fourth feature layer, `application/`
  (`services`/`coordinators`/`facades`/`runtime`), matching the 4-layer Clean
  Architecture model (Presentation → Application → Domain ← Data). Presentation
  may now import the application layer; application may import only domain.
  `application/` is optional per feature (not required by ARCH201–203) and is no
  longer flagged as an unrecognized folder (ARCH210). Its sub-folder vocabulary
  is enforced by ARCH211.
- `architecture`: expanded the folder vocabulary to match the canonical
  feature layout — `data/{data_sources,mappers,dto}`,
  `domain/{value_objects,services}`, and `presentation/{controllers,dialogs}`
  are now recognized sub-folders. `lib/shared/` and `lib/initialization/` are
  recognized as top-level shared infrastructure (like `lib/core/`), so they no
  longer trip ARCH212.
- `architecture`: routing's blessed home moved from `core/config/router/` to the
  top-level `lib/routing/` (ARCH401–403). Route definitions under
  `core/config/router/` are now flagged instead.
- `architecture`: `presentation/painters/` and `presentation/styles/` are now
  built-in vocabulary, and the folder vocabulary is extensible via a new
  `architecture:` section in
  `.flutter_cleanup.yaml` (`sublayers:` per layer and `top_level:`). Extras are
  additive and only relax the structure warnings (ARCH210–212); the layer/purity
  rules still apply.
- `architecture`: new analyzer/command detecting Clean Architecture +
  Feature-Based + Riverpod violations (ARCH101–503) from the Dart AST. Builds an
  import/dependency graph, classifies each file's layer, and runs a categorized
  rule set (layer purity, structure/placement, Riverpod injection, routing,
  feature boundaries incl. cross-feature imports, circular dependencies, and
  fan-out). Emits findings with file/line/confidence plus an architecture
  **score**, a per-category `summary`, `violationsByCode`, and a feature
  `dependencies` map; `--report` prints the dependency tree. Analysis is
  syntactic (`"analysisMode": "syntactic-ast"`), so heuristic rules are
  confidence-graded. Included in `all` and `all --json`.
- `Finding` gains optional `line`, `column`, and `confidence` fields (omitted
  from JSON when unset, so existing analyzers' output is unchanged).
- VS Code extension: new **Analyze Architecture** command publishes ARCH
  violations to the Problems panel via a `DiagnosticCollection`, with the score
  surfaced in a notification. CLI invocation extracted to a shared module; the
  vscode-free diagnostic mapping is unit-tested under Node (mocha).

## 1.0.0

- Initial CLI foundation built on `package:args` `CommandRunner`.
- Commands: `scan`, `unused-assets`, and `version`.
- Project structure validation (pubspec.yaml, lib/, optional assets/).
- ANSI-aware formatted terminal output.
- `analysis/` layer with a framework-agnostic `Analyzer` interface and
  `AnalysisResult`, plus a uniform `Finding` model (`Severity` info/warning/error).
- Format-aware `ReportPrinter` and `OutputFormat` (text now, JSON reserved) and
  a `FlutterCleanupCommand` base command, preparing for `--json` and the
  `unused-files` / `graph` / `doctor` commands.
- `unused-assets`: first real analyzer. Reads directory-style entries from
  `flutter > assets`, recursively discovers asset files, and reports any not
  referenced as a string literal in `lib/**` (string/RegExp matching, no AST).
- `unused-files`: reachability analyzer. Builds an import/export/part graph of
  `lib/**`, treats `lib/main.dart` as the root, and reports unreachable Dart
  files (directive parsing, no AST).
