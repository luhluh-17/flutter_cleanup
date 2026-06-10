import 'dart_file_info.dart';

/// The project's internal import dependencies, at both file and feature
/// granularity, built once during context creation.
///
/// Rules query this (`dependsOn`, `featureImports`) instead of re-walking each
/// file's imports, and it is the substrate for cycle detection (ARCH502) and
/// fan-out (ARCH503) — and for future graph visualization / dependency reports.
class DependencyGraph {
  DependencyGraph({
    required this.fileImports,
    required this.featureImports,
  });

  /// file relPath → set of internal file relPaths it imports.
  final Map<String, Set<String>> fileImports;

  /// feature → set of *other* features it depends on.
  final Map<String, Set<String>> featureImports;

  /// Builds the graph from the parsed files.
  factory DependencyGraph.build(List<DartFileInfo> files) {
    final known = {for (final f in files) f.relPath};
    final fileImports = <String, Set<String>>{};
    final featureImports = <String, Set<String>>{};

    for (final file in files) {
      final fromFeature = file.layer.feature;
      final fileEdges = fileImports.putIfAbsent(file.relPath, () => {});

      for (final import in file.imports) {
        if (!import.isInternal) continue;
        final target = import.targetRelPath;
        if (target == null) continue;
        if (known.contains(target)) fileEdges.add(target);

        final toFeature = import.targetLayer?.feature;
        if (fromFeature != null &&
            toFeature != null &&
            toFeature != fromFeature) {
          featureImports.putIfAbsent(fromFeature, () => {}).add(toFeature);
        }
      }

      // Ensure every feature appears as a key, even with no outgoing edges.
      if (fromFeature != null) {
        featureImports.putIfAbsent(fromFeature, () => {});
      }
    }

    return DependencyGraph(
      fileImports: fileImports,
      featureImports: featureImports,
    );
  }

  /// Whether file [from] imports file [to] (internal, file-level).
  bool dependsOn(String from, String to) =>
      fileImports[from]?.contains(to) ?? false;

  /// The number of distinct other features [feature] depends on (fan-out).
  int fanOut(String feature) => featureImports[feature]?.length ?? 0;

  /// Detects circular dependencies between features.
  ///
  /// Returns one representative cycle per cyclic group (deduplicated by the set
  /// of features involved), each as a path that returns to its start, e.g.
  /// `[auth, profile, auth]`. Output is deterministic (features visited in
  /// sorted order).
  List<List<String>> featureCycles() {
    final result = <List<String>>[];
    final seenGroups = <String>{};
    final visited = <String>{};
    final stack = <String>[];
    final onStack = <String>{};

    void dfs(String node) {
      visited.add(node);
      stack.add(node);
      onStack.add(node);

      final neighbors = (featureImports[node] ?? const <String>{}).toList()
        ..sort();
      for (final next in neighbors) {
        if (onStack.contains(next)) {
          final start = stack.indexOf(next);
          final cycle = [...stack.sublist(start), next];
          final key = (cycle.toSet().toList()..sort()).join(',');
          if (seenGroups.add(key)) result.add(cycle);
        } else if (!visited.contains(next)) {
          dfs(next);
        }
      }

      stack.removeLast();
      onStack.remove(node);
    }

    for (final node in featureImports.keys.toList()..sort()) {
      if (!visited.contains(node)) dfs(node);
    }
    return result;
  }
}
