import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A warning/error threshold pair for a single maintainability metric.
///
/// A measured value `>= error` maps to [Severity.error], `>= warning` (but below
/// `error`) maps to [Severity.warning], and anything below `warning` produces no
/// finding. Both bounds are inclusive lower bounds.
class Threshold {
  const Threshold({required this.warning, required this.error});

  /// Smallest value that triggers a `warning` finding (inclusive).
  final int warning;

  /// Smallest value that triggers an `error` finding (inclusive).
  final int error;
}

/// Project-specific thresholds for the [MaintainabilityAnalyzer], read from the
/// `maintainability:` section of `.flutter_cleanup.yaml`.
///
/// ```yaml
/// maintainability:
///   enabled: true
///   file_lines:           { warning: 500, error: 1000 }
///   method_lines:         { warning: 50,  error: 100 }
///   build_method_lines:   { warning: 100, error: 200 }
///   widget_count:         { warning: 10,  error: 20 }
///   widget_nesting_depth: { warning: 6,   error: 10 }
/// ```
///
/// Parsing is tolerant (mirrors [ArchitectureConfig] / [IgnoreService]): a
/// missing file/section, malformed YAML, or wrong types fall back to the
/// per-field defaults below. Overrides are partial — setting only
/// `file_lines.warning` keeps every other default intact.
class MaintainabilityConfig {
  const MaintainabilityConfig({
    this.enabled = true,
    this.fileLines = defaultFileLines,
    this.methodLines = defaultMethodLines,
    this.buildMethodLines = defaultBuildMethodLines,
    this.widgetCount = defaultWidgetCount,
    this.widgetNestingDepth = defaultWidgetNestingDepth,
  });

  /// The all-defaults config used when no `maintainability:` section applies.
  static const MaintainabilityConfig empty = MaintainabilityConfig();

  /// The config-file key (shared with [IgnoreService]).
  static const String configFileName = '.flutter_cleanup.yaml';

  // Per-metric defaults (from the analyzer spec).
  static const Threshold defaultFileLines = Threshold(warning: 500, error: 1000);
  static const Threshold defaultMethodLines = Threshold(warning: 50, error: 100);
  static const Threshold defaultBuildMethodLines =
      Threshold(warning: 100, error: 200);
  static const Threshold defaultWidgetCount = Threshold(warning: 10, error: 20);
  static const Threshold defaultWidgetNestingDepth =
      Threshold(warning: 6, error: 10);

  /// Whether the analyzer runs at all. When false the analyzer returns no
  /// findings.
  final bool enabled;

  /// Total non-empty source lines per file.
  final Threshold fileLines;

  /// Source lines per method/function (excluding `build`).
  final Threshold methodLines;

  /// Source lines of a `build(BuildContext)` method.
  final Threshold buildMethodLines;

  /// Widget classes declared in a single file.
  final Threshold widgetCount;

  /// Maximum widget-tree nesting depth within a `build` method.
  final Threshold widgetNestingDepth;

  /// Loads the `maintainability:` section from `<root>/.flutter_cleanup.yaml`.
  ///
  /// Returns [empty] when the file is absent, unreadable, not a map, or has no
  /// usable `maintainability:` section.
  factory MaintainabilityConfig.forProject(String root) {
    final file = File(p.join(root, configFileName));
    if (!file.existsSync()) return empty;

    final dynamic doc;
    try {
      doc = loadYaml(file.readAsStringSync());
    } catch (_) {
      return empty; // Malformed YAML — fall back to defaults only.
    }
    if (doc is! YamlMap) return empty;

    final dynamic section = doc['maintainability'];
    if (section is! YamlMap) return empty;

    return MaintainabilityConfig(
      enabled: _readBool(section['enabled'], defaultValue: true),
      fileLines: _readThreshold(section['file_lines'], defaultFileLines),
      methodLines: _readThreshold(section['method_lines'], defaultMethodLines),
      buildMethodLines:
          _readThreshold(section['build_method_lines'], defaultBuildMethodLines),
      widgetCount: _readThreshold(section['widget_count'], defaultWidgetCount),
      widgetNestingDepth: _readThreshold(
          section['widget_nesting_depth'], defaultWidgetNestingDepth),
    );
  }

  /// Reads a `{warning, error}` map, falling back to [fallback] for each missing
  /// or non-integer bound (partial overrides are supported).
  static Threshold _readThreshold(dynamic node, Threshold fallback) {
    if (node is! YamlMap) return fallback;
    return Threshold(
      warning: _readInt(node['warning'], fallback.warning),
      error: _readInt(node['error'], fallback.error),
    );
  }

  static int _readInt(dynamic node, int defaultValue) =>
      node is int ? node : defaultValue;

  static bool _readBool(dynamic node, {required bool defaultValue}) =>
      node is bool ? node : defaultValue;
}
