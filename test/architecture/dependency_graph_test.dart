import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:test/test.dart';

void main() {
  test('dependsOn reflects file-level edges', () {
    final graph = DependencyGraph(
      fileImports: {
        'lib/a.dart': {'lib/b.dart'},
        'lib/b.dart': {},
      },
      featureImports: {},
    );
    expect(graph.dependsOn('lib/a.dart', 'lib/b.dart'), isTrue);
    expect(graph.dependsOn('lib/b.dart', 'lib/a.dart'), isFalse);
  });

  test('fanOut counts distinct depended-on features', () {
    final graph = DependencyGraph(
      fileImports: {},
      featureImports: {
        'auth': {'profile', 'settings', 'billing'},
        'profile': {},
      },
    );
    expect(graph.fanOut('auth'), 3);
    expect(graph.fanOut('profile'), 0);
    expect(graph.fanOut('unknown'), 0);
  });

  test('featureCycles detects a 2-feature cycle and returns the path', () {
    final graph = DependencyGraph(
      fileImports: {},
      featureImports: {
        'auth': {'profile'},
        'profile': {'auth'},
      },
    );
    final cycles = graph.featureCycles();
    expect(cycles, hasLength(1));
    // Path returns to its start, e.g. [auth, profile, auth].
    final cycle = cycles.single;
    expect(cycle.first, cycle.last);
    expect(cycle.toSet(), {'auth', 'profile'});
  });

  test('featureCycles detects a 3-feature cycle', () {
    final graph = DependencyGraph(
      fileImports: {},
      featureImports: {
        'a': {'b'},
        'b': {'c'},
        'c': {'a'},
      },
    );
    final cycles = graph.featureCycles();
    expect(cycles, hasLength(1));
    expect(cycles.single.toSet(), {'a', 'b', 'c'});
  });

  test('a DAG has no cycles', () {
    final graph = DependencyGraph(
      fileImports: {},
      featureImports: {
        'a': {'b', 'c'},
        'b': {'c'},
        'c': {},
      },
    );
    expect(graph.featureCycles(), isEmpty);
  });
}
