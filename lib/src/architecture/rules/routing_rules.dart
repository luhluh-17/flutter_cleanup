import '../../models/finding.dart';
import '../architecture_context.dart';
import '../architecture_violation.dart';
import '../ast/ast_scanner.dart';
import 'architecture_rule.dart';

/// ARCH401–403 — routing must be centralized in `lib/routing`.
///
/// - 401: a routing definition (`GoRouter`/`GoRoute`) anywhere outside
///   `lib/routing` and outside features (e.g. `lib/app.dart`, `core/`).
/// - 402: a feature instantiates its own `GoRouter`.
/// - 403: a feature contains a route-registration file (name matches `rout…`).
///
/// A single rule handles all three so each file is reported once (a feature's
/// `GoRouter` is 402, not also 403/401).
class RoutingRule implements ArchitectureRule {
  const RoutingRule();

  static final _routeFileName = RegExp('rout', caseSensitive: false);
  static const _routingTypes = {'GoRouter', 'GoRoute'};

  @override
  String get name => 'routing';

  @override
  Iterable<ArchitectureViolation> check(ArchitectureContext context) sync* {
    for (final file in context.files) {
      if (file.layer.isRouterDir) continue; // the blessed location

      int? goRouterOffset;
      int? routingOffset;
      for (final instantiation in findInstantiations(file.unit)) {
        if (instantiation.typeName == 'GoRouter') {
          goRouterOffset ??= instantiation.offset;
        }
        if (_routingTypes.contains(instantiation.typeName)) {
          routingOffset ??= instantiation.offset;
        }
      }

      final feature = file.layer.feature;
      if (feature != null) {
        if (goRouterOffset != null) {
          yield ArchitectureViolation(
            code: 'ARCH402',
            severity: Severity.error,
            confidence: Confidence.high,
            filePath: file.relPath,
            line: file.lineAt(goRouterOffset),
            featureName: feature,
            message: 'Feature "$feature" must not define its own GoRouter. '
                'Register routes in lib/routing.',
          );
        } else if (_routeFileName.hasMatch(_basename(file.relPath))) {
          yield ArchitectureViolation(
            code: 'ARCH403',
            severity: Severity.warning,
            confidence: Confidence.medium,
            filePath: file.relPath,
            line: 1,
            featureName: feature,
            message: 'Route-registration file inside feature "$feature". '
                'Routing should live in lib/routing.',
          );
        }
      } else if (routingOffset != null) {
        yield ArchitectureViolation(
          code: 'ARCH401',
          severity: Severity.warning,
          confidence: Confidence.high,
          filePath: file.relPath,
          line: file.lineAt(routingOffset),
          message: 'Routing definitions should only exist in lib/routing.',
        );
      }
    }
  }

  String _basename(String relPath) => relPath.split('/').last;
}
