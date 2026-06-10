/// Renders a feature-dependency map as an ASCII tree.
///
/// A cheap, high-signal read straight off the dependency graph — no extra
/// analysis. Given `{auth: [profile, settings], dashboard: [auth]}` it produces:
///
/// ```
/// auth
/// ├── profile
/// └── settings
/// dashboard
/// └── auth
/// ```
///
/// Features are listed in sorted order; a feature with no dependencies is shown
/// as a leaf (`feature (no dependencies)`).
String renderDependencyTree(Map<String, List<String>> dependencies) {
  if (dependencies.isEmpty) return 'No features found.';

  final buffer = StringBuffer();
  final features = dependencies.keys.toList()..sort();
  for (final feature in features) {
    final deps = [...dependencies[feature] ?? const <String>[]]..sort();
    if (deps.isEmpty) {
      buffer.writeln('$feature (no dependencies)');
      continue;
    }
    buffer.writeln(feature);
    for (var i = 0; i < deps.length; i++) {
      final connector = i == deps.length - 1 ? '└── ' : '├── ';
      buffer.writeln('$connector${deps[i]}');
    }
  }
  return buffer.toString().trimRight();
}
