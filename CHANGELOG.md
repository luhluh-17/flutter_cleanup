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
