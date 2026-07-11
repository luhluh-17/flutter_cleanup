## Unreleased

- `maintainability`: **five false-positive fixes**, cross-checked against a
  large real-world Flutter workspace:
  - **Sealed unions pass the public-class-count rule.** A direct subtype
    (`extends`/`with`/`implements`) of a `sealed` class declared in the same
    file is a supporting type: the language requires every subtype of a sealed
    class to stay in its library, so "move each class into its own file" was
    unactionable. Abstract (non-sealed) hierarchies still count.
  - **Static-only namespace classes pass the public-class-count rule.** The
    `class Tokens { Tokens._(); static const ... }` idiom (all members static,
    no public way to instantiate) no longer counts; a class with an implicit
    public constructor still does.
  - **Method and `build()` lengths now count code lines of the body**, the same
    rule file length already used: blank lines, comments, and the signature
    (including `@override` and multi-line parameter lists) no longer count.
  - **`build(BuildContext, WidgetRef)` is a build method.** Riverpod
    `ConsumerWidget`/`HookConsumerWidget` builds were measured against the
    30-line method limit instead of the 60-line build limit (and skipped
    nesting-depth analysis) because detection required exactly one parameter.
  - **`super.key` no longer counts toward the constructor-parameter limit** —
    mandatory widget boilerplate, not API surface. A regular parameter that
    happens to be named `key` still counts.
- `maintainability`: new **`exempt_methods`** config key — method/function
  names the method-length rule skips entirely, defaulting to `[copyWith]`
  (mechanical data-class boilerplate whose length tracks the field count, not
  complexity). Set `exempt_methods: []` to disable the exemption, or list your
  own names (e.g. `toJson`, `props`).
- `maintainability`: the **public-class-count** rule no longer counts a public
  class that a sibling public class in the same file references — by inheritance
  (`extends`/`implements`/`with`) or composition (a field/return/parameter type,
  generic type argument, factory result, or a construction/`throw` in a body).
  Cohesive pairs that belong together — a contract and its implementation, a
  carrier and its element type, a widget and its own public `State` — no longer
  trip the limit, while two genuinely unrelated public classes still do. Coupling
  only through a shared top-level function, enum, or extension (or indirectly via
  a `part` file or typedef alias) does not exempt a class, consistent with the
  analyzer's `syntactic-ast` mode.
- `maintainability`: **retuned to a single accepted-standard limit per metric**
  (was a `warning`/`error` pair). A value at or below the limit passes; above it
  is reported as a `warning`. New defaults: widget file ≤ 250 lines, controller
  ≤ 300, generic file ≤ 300, `build()` ≤ 60, method ≤ 30, widget nesting ≤ 5,
  public classes ≤ 1 per file, constructor params ≤ 8, and folder ≤ 15 Dart
  files. The file-length limit is chosen by **classifying** each file as a
  controller (`*_controller.dart`, a `*Controller` class, or a class extending
  `ChangeNotifier`/`StateNotifier`/`Notifier`/`Cubit`/`Bloc`/… ), a widget file,
  or a generic file. The **widget-count** metric is replaced by a **public-class
  count** (max one public top-level class per file), and two metrics are new:
  **constructor parameter count** and **folder file count**. Findings are now
  **grouped by metric** in the text report, each under a sub-heading showing its
  limit, and every finding carries a metric-specific `rule` id
  (`widget_file_length`, `controller_length`, `file_length`,
  `build_method_length`, `method_length`, `widget_nesting_depth`,
  `public_class_count`, `constructor_params`, `folder_file_count`) instead of the
  shared `maintainability`. Config keys change accordingly — each is now a single
  integer (e.g. `method_lines: 30`) rather than `{ warning, error }`; see
  [Maintainability limits](README.md#maintainability-limits).
- `maintainability`: widget nesting depth no longer counts decoration, border,
  constraint and gradient config objects as tree levels. `InputDecoration`,
  `BoxDecoration`, `ShapeDecoration`, `BoxConstraints`, `BoxShadow`, the
  `*InputBorder`/`ShapeBorder` types and `LinearGradient`/`RadialGradient`/
  `SweepGradient` were treated as structural widgets, inflating reported depth
  by one per config object — a labeled `TextField` read as depth 6 and a
  decorated `Container` as depth 7. These now join the existing blocklist
  (alongside `EdgeInsets`, `TextStyle`, `Border`, …), so the metric reflects
  real widget nesting.
- `architecture`: feature-completeness is no longer a full-vertical-slice check.
  Because every layer points inward at `domain`, a feature may legitimately be
  UI-only (domain/data shared in `core/`), logic-only, or a headless service —
  so missing `presentation`/`data` no longer warns. The only flagged
  incompleteness is now a `data/` layer with no `domain/` layer to back it
  (ARCH202); the former ARCH201 (missing data) and ARCH203 (missing
  presentation) are retired.
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
