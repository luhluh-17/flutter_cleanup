import '../models/finding.dart';
import 'definition/layer.dart';

/// The five families of architecture rules, used for grouping and scoring.
///
/// The category is derived from the ARCH code's hundreds digit (`ARCH1xx` →
/// [layer], `ARCH5xx` → [feature]) so a violation only needs to carry its code.
/// Each category has a score [weight]: architectural damage is not uniform, so
/// a feature cycle (5) costs far more than a misplaced file (2).
enum RuleCategory {
  layer('layer', 3),
  structure('structure', 2),
  riverpod('riverpod', 2),
  routing('routing', 2),
  feature('feature', 5);

  const RuleCategory(this.key, this.weight);

  /// Stable lowercase name used as the JSON `summary` key.
  final String key;

  /// Points deducted from the architecture score per violation in this category.
  final int weight;

  /// Derives the category from an `ARCHnxx` code via its hundreds digit.
  static RuleCategory fromCode(String code) {
    final digit = code.length >= 5 ? code[4] : '0';
    switch (digit) {
      case '1':
        return RuleCategory.layer;
      case '2':
        return RuleCategory.structure;
      case '3':
        return RuleCategory.riverpod;
      case '4':
        return RuleCategory.routing;
      case '5':
        return RuleCategory.feature;
      default:
        return RuleCategory.structure;
    }
  }
}

/// A rule violation in the analyzer's rich internal form.
///
/// Rules emit [ArchitectureViolation]s, not [Finding]s, so they can carry extra
/// structural metadata ([featureName], [layer], [relatedFiles], [cyclePath],
/// [dependencyPath]) that future phases — a dashboard, a graph view, quick fixes
/// — will want, without bloating the lean [Finding] that the shared output
/// pipeline (JSON → VS Code diagnostic) carries today. [toFinding] performs that
/// projection.
class ArchitectureViolation {
  ArchitectureViolation({
    required this.code,
    required this.severity,
    required this.confidence,
    required this.filePath,
    required this.message,
    this.line,
    this.column,
    this.featureName,
    this.layer,
    this.relatedFiles = const [],
    this.cyclePath = const [],
    this.dependencyPath = const [],
  });

  /// The `ARCHnxx` rule code.
  final String code;

  final Severity severity;
  final Confidence confidence;

  /// Project-relative POSIX path of the offending file.
  final String filePath;

  final String message;

  /// 1-based line/column of the offending node, when known.
  final int? line;
  final int? column;

  /// Owning feature, when relevant.
  final String? featureName;

  /// Layer of the offending file, when relevant.
  final Layer? layer;

  /// Other files implicated (e.g. the imported file). Phase-3 metadata.
  final List<String> relatedFiles;

  /// For ARCH502, the feature cycle (`[auth, profile, auth]`).
  final List<String> cyclePath;

  /// For dependency violations, the import chain. Phase-3 metadata.
  final List<String> dependencyPath;

  /// The category this violation belongs to (derived from [code]).
  RuleCategory get category => RuleCategory.fromCode(code);

  /// Projects this violation onto the lean [Finding] used by the output layer.
  Finding toFinding() => Finding(
        rule: code,
        path: filePath,
        severity: severity,
        message: message,
        line: line,
        column: column,
        confidence: confidence,
      );
}
