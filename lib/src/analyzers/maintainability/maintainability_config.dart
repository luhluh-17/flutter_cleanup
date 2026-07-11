import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Project-specific limits for the [MaintainabilityAnalyzer], read from the
/// `maintainability:` section of `.flutter_cleanup.yaml`.
///
/// Every metric is a single **maximum** (an accepted standard): a measured value
/// at or below the limit is fine, and a value *strictly greater than* the limit
/// is reported. This mirrors how the standards are written ("≤ 250 lines").
///
/// ```yaml
/// maintainability:
///   enabled: true
///   widget_file_lines:    250   # file that declares a widget class
///   controller_lines:     300   # file classified as a controller
///   file_lines:           300   # generic fallback (neither widget nor controller)
///   build_method_lines:    60
///   method_lines:          30
///   widget_nesting_depth:   5
///   max_public_classes:     1
///   constructor_params:     8
///   folder_files:          15
/// ```
///
/// Parsing is tolerant (mirrors [ArchitectureConfig] / [IgnoreService]): a
/// missing file/section, malformed YAML, or wrong types fall back to the
/// per-field defaults below. Overrides are partial — setting only
/// `method_lines` keeps every other default intact.
class MaintainabilityConfig {
  const MaintainabilityConfig({
    this.enabled = true,
    this.widgetFileLines = defaultWidgetFileLines,
    this.controllerLines = defaultControllerLines,
    this.fileLines = defaultFileLines,
    this.buildMethodLines = defaultBuildMethodLines,
    this.methodLines = defaultMethodLines,
    this.widgetNestingDepth = defaultWidgetNestingDepth,
    this.maxPublicClasses = defaultMaxPublicClasses,
    this.constructorParams = defaultConstructorParams,
    this.folderFiles = defaultFolderFiles,
  });

  /// The all-defaults config used when no `maintainability:` section applies.
  static const MaintainabilityConfig empty = MaintainabilityConfig();

  /// The config-file key (shared with [IgnoreService]).
  static const String configFileName = '.flutter_cleanup.yaml';

  // Per-metric defaults (the accepted-standards limits).
  static const int defaultWidgetFileLines = 250;
  static const int defaultControllerLines = 300;
  static const int defaultFileLines = 300;
  static const int defaultBuildMethodLines = 60;
  static const int defaultMethodLines = 30;
  static const int defaultWidgetNestingDepth = 5;
  static const int defaultMaxPublicClasses = 1;
  static const int defaultConstructorParams = 8;
  static const int defaultFolderFiles = 15;

  /// Whether the analyzer runs at all. When false the analyzer returns no
  /// findings.
  final bool enabled;

  /// Max lines of code in a file that declares a widget class.
  final int widgetFileLines;

  /// Max lines of code in a file classified as a controller.
  final int controllerLines;

  /// Max lines of code in a file that is neither a widget nor a controller.
  final int fileLines;

  /// Max source lines of a `build(BuildContext)` method.
  final int buildMethodLines;

  /// Max source lines of any other method/function (excluding `build`).
  final int methodLines;

  /// Max widget-tree nesting depth within a `build` method.
  final int widgetNestingDepth;

  /// Max number of public top-level classes declared in a single file.
  ///
  /// A public class that another public class in the same file references (by
  /// inheritance or composition) is treated as a supporting type and does not
  /// count toward this limit — see [MaintainabilityAnalyzer] Rule 5.
  final int maxPublicClasses;

  /// Max number of parameters on any single constructor.
  final int constructorParams;

  /// Max number of Dart files directly inside a single folder under `lib/`.
  final int folderFiles;

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
      widgetFileLines:
          _readInt(section['widget_file_lines'], defaultWidgetFileLines),
      controllerLines:
          _readInt(section['controller_lines'], defaultControllerLines),
      fileLines: _readInt(section['file_lines'], defaultFileLines),
      buildMethodLines:
          _readInt(section['build_method_lines'], defaultBuildMethodLines),
      methodLines: _readInt(section['method_lines'], defaultMethodLines),
      widgetNestingDepth:
          _readInt(section['widget_nesting_depth'], defaultWidgetNestingDepth),
      maxPublicClasses:
          _readInt(section['max_public_classes'], defaultMaxPublicClasses),
      constructorParams:
          _readInt(section['constructor_params'], defaultConstructorParams),
      folderFiles: _readInt(section['folder_files'], defaultFolderFiles),
    );
  }

  static int _readInt(dynamic node, int defaultValue) =>
      node is int ? node : defaultValue;

  static bool _readBool(dynamic node, {required bool defaultValue}) =>
      node is bool ? node : defaultValue;
}
