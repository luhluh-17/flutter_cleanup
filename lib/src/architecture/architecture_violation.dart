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

/// Actionable fix suggestions per ARCH code, surfaced alongside each finding
/// (text mode prints them under the violation; JSON exposes `recommendation`).
///
/// One entry per code keeps suggestions consistent everywhere a code can fire.
/// Returns null for unknown codes so forgotten entries degrade gracefully.
String? recommendationFor(String code) => _recommendations[code];

const Map<String, String> _recommendations = {
  // ARCH1xx — layer dependency & purity
  'ARCH101': 'Define an abstraction in domain and implement it in data; '
      'domain must stay framework-free.',
  'ARCH102': 'Convert models to entities in a data-layer mapper; domain '
      'should only know entities.',
  'ARCH103': 'Call a use case or provider instead; only data/repositories '
      'may touch datasources.',
  'ARCH104': 'Depend on the domain repository contract and resolve the '
      'implementation via a provider.',
  'ARCH105': 'Go through a use case or provider, or move the imported type '
      'into domain/entities if it is an entity.',
  'ARCH106': 'Invert the dependency: declare a contract in domain and '
      'implement it in the outer layer.',
  'ARCH107': 'Construct Dio inside a data-layer datasource and inject it; '
      'presentation should call use cases.',
  'ARCH108': 'Instantiate datasources in the data layer and expose them via '
      'repositories and providers.',
  'ARCH109': 'Move toJson/fromJson into a data-layer model or mapper and '
      'pass typed objects to the UI.',
  'ARCH110': 'Obtain the repository from a Riverpod provider '
      '(ref.read/ref.watch) instead of constructing it.',
  // ARCH2xx — structure & element placement
  'ARCH202': 'Add the domain/ layer (entities, repositories, usecases) the '
      'data layer implements, or move the data code elsewhere — presentation '
      'and data are optional, but a data layer needs a domain to back it.',
  'ARCH204': 'Move the use case into domain/usecases/.',
  'ARCH205': 'Move the abstract repository into domain/repositories/ so '
      'other layers can depend on the contract.',
  'ARCH206': 'Move the implementation into data/repositories/.',
  'ARCH207': 'Move the model into data/models/, or make it an entity in '
      'domain/entities if it has no serialization.',
  'ARCH208': 'Move the entity into domain/entities/.',
  'ARCH209': 'Declare "implements <Name>Repository", creating the contract '
      'in domain/repositories if needed.',
  'ARCH210': 'Move the folder\'s contents into data/, domain/, application/, or '
      'presentation/ (orchestration fits application/services; business rules '
      'fit domain/usecases; infrastructure fits data/).',
  'ARCH211': 'Rename to the standard vocabulary (screens → pages, '
      'state → providers/controllers, domain models → entities) or nest it '
      'under a recognized sub-folder.',
  'ARCH212': 'Move shared code into lib/core/ (or lib/shared/) and feature code '
      'into lib/features/<feature>/ (routing belongs in lib/routing).',
  // ARCH3xx — Riverpod
  'ARCH301': 'Inject the dependency through a provider '
      '(ref.watch/ref.read) instead of constructing it in the notifier.',
  // ARCH4xx — routing
  'ARCH401': 'Move routing definitions into lib/routing/.',
  'ARCH402': 'Use the central GoRouter in lib/routing and contribute '
      'routes there.',
  'ARCH403': 'Move route registration into lib/routing/; features '
      'should expose pages, not routes.',
  // ARCH5xx — feature boundaries
  'ARCH501': 'Extract the shared code into core/, or depend on the other '
      'feature\'s domain contract (domain/repositories) instead.',
  'ARCH502': 'Break the cycle: invert one direction via a domain contract '
      'or move the shared types into core/.',
  'ARCH503': 'Split the feature or extract shared building blocks into '
      'core/ to reduce fan-out.',
};

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
        recommendation: recommendationFor(code),
      );
}
