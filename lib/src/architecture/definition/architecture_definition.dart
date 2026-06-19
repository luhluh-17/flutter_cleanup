import '../layer_classifier.dart';
import 'layer.dart';
import 'layer_info.dart';

/// A pluggable description of an architecture style.
///
/// Clean Architecture is the only implementation today
/// ([CleanArchitectureDefinition]), but abstracting the three things that vary
/// between styles — how paths map to layers, which import directions are legal,
/// and which infrastructure packages a pure layer may not touch — is the seam
/// that lets a future Phase 4 load these from YAML or describe other styles
/// (DDD, MVC, Feature-Sliced) without rewriting the rule engine.
abstract interface class ArchitectureDefinition {
  /// Maps a project-relative POSIX path to its [LayerInfo].
  LayerInfo classify(String relPath);

  /// Whether a file in layer [from] is allowed to import a file in layer [to].
  ///
  /// Encodes the allowed-direction matrix; rules that check generic layer
  /// dependencies consult this instead of hard-coding pairs.
  bool canImport(Layer from, Layer to);

  /// Whether [packageName] (the `<name>` in `package:<name>/…`) is an
  /// infrastructure dependency the [Layer.domain] layer must never import.
  bool isForbiddenInDomain(String packageName);
}

/// The Clean Architecture + Feature-Based + Riverpod style this tool targets.
class CleanArchitectureDefinition implements ArchitectureDefinition {
  const CleanArchitectureDefinition();

  static const _classifier = LayerClassifier();

  /// Infrastructure packages the domain layer must stay free of (ARCH101).
  ///
  /// Matched by exact name or `<name>_` prefix, so `firebase` also rejects
  /// `firebase_auth`/`cloud_firestore`-style siblings handled below.
  static const _forbiddenDomainPackages = {
    'flutter',
    'dio',
    'retrofit',
    'firebase',
    'firebase_core',
    'firebase_auth',
    'cloud_firestore',
    'hive',
    'hive_flutter',
    'drift',
    'shared_preferences',
  };

  @override
  LayerInfo classify(String relPath) => _classifier.classify(relPath);

  @override
  bool canImport(Layer from, Layer to) {
    // Anyone may use shared infrastructure; same-layer imports are always fine;
    // imports from outside the feature layers (unknown app shell files) are not
    // constrained by the matrix.
    if (to == Layer.core) return true;
    if (from == to) return true;
    if (!from.isFeatureLayer || !to.isFeatureLayer) return true;

    // Dependencies flow inward toward domain.
    switch (from) {
      case Layer.presentation:
        return to == Layer.application || to == Layer.domain; // not data
      case Layer.application:
        return to == Layer.domain; // not presentation or data
      case Layer.data:
        return to == Layer.domain; // not presentation or application
      case Layer.domain:
        return false; // domain depends on nothing outward
      case Layer.core:
      case Layer.unknown:
        return true;
    }
  }

  @override
  bool isForbiddenInDomain(String packageName) {
    if (packageName == 'flutter' || packageName.startsWith('firebase')) {
      return true;
    }
    return _forbiddenDomainPackages.contains(packageName);
  }
}
