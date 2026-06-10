import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('directory_tree_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- Fixture helpers -------------------------------------------------------

  /// Creates the directory at project-relative POSIX path [rel].
  void mkdir(String rel) {
    Directory(p.join(tempDir.path, p.joinAll(rel.split('/'))))
        .createSync(recursive: true);
  }

  /// Writes an (empty) file at project-relative POSIX path [rel].
  void writeFile(String rel) {
    final file = File(p.join(tempDir.path, p.joinAll(rel.split('/'))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('');
  }

  DirectoryTreeNode build({
    String root = 'lib',
    int? maxDepth,
    List<String> ignorePatterns = const [],
  }) {
    return const DirectoryTreeBuilder().build(
      projectRoot: tempDir.path,
      rootDir: p.join(tempDir.path, p.joinAll(root.split('/'))),
      ignoreService: IgnoreService(ignorePatterns),
      maxDepth: maxDepth,
    );
  }

  /// Flattens [node] into `path -> child names` for easy assertions.
  Map<String, List<String>> flatten(DirectoryTreeNode node, [String? prefix]) {
    final path = prefix == null ? node.name : '$prefix/${node.name}';
    return {
      path: [for (final c in node.children) c.name],
      for (final child in node.children) ...flatten(child, path),
    };
  }

  // --- Tests -----------------------------------------------------------------

  test('empty lib directory yields a root with no children', () {
    mkdir('lib');

    final tree = build();

    expect(tree.name, 'lib');
    expect(tree.children, isEmpty);
  });

  test('nested directories are represented recursively', () {
    mkdir('lib/core');
    mkdir('lib/features/activities');
    mkdir('lib/features/workflow');
    mkdir('lib/initialization');

    final tree = build();

    expect(flatten(tree), {
      'lib': ['core', 'features', 'initialization'],
      'lib/core': <String>[],
      'lib/features': ['activities', 'workflow'],
      'lib/features/activities': <String>[],
      'lib/features/workflow': <String>[],
      'lib/initialization': <String>[],
    });
  });

  test('files are ignored — directories only', () {
    mkdir('lib/core');
    writeFile('lib/main.dart');
    writeFile('lib/core/app.dart');

    final tree = build();

    expect(flatten(tree), {
      'lib': ['core'],
      'lib/core': <String>[],
    });
  });

  test('IgnoreService prunes matching directories and their subtrees', () {
    mkdir('lib/core');
    mkdir('lib/generated/proto');
    mkdir('lib/features/build/cache');

    final tree =
        build(ignorePatterns: ['lib/generated', '**/build']);

    expect(flatten(tree), {
      'lib': ['core', 'features'],
      'lib/core': <String>[],
      'lib/features': <String>[],
    });
  });

  test('maxDepth limits traversal depth', () {
    mkdir('lib/features/activities/widgets');

    final depth1 = build(maxDepth: 1);
    expect(flatten(depth1), {
      'lib': ['features'],
      'lib/features': <String>[],
    });

    final depth2 = build(maxDepth: 2);
    expect(flatten(depth2), {
      'lib': ['features'],
      'lib/features': ['activities'],
      'lib/features/activities': <String>[],
    });
  });

  test('children are sorted alphabetically regardless of creation order', () {
    mkdir('lib/zeta');
    mkdir('lib/alpha');
    mkdir('lib/mid');
    mkdir('lib/beta');

    final tree = build();

    expect([for (final c in tree.children) c.name],
        ['alpha', 'beta', 'mid', 'zeta']);
  });

  test('toJson serializes the full hierarchy', () {
    mkdir('lib/core');
    mkdir('lib/features/activities');

    final tree = build();

    expect(tree.toJson(), {
      'name': 'lib',
      'children': [
        {'name': 'core', 'children': <Object?>[]},
        {
          'name': 'features',
          'children': [
            {'name': 'activities', 'children': <Object?>[]},
          ],
        },
      ],
    });
  });

  test('root name uses project-relative POSIX paths for nested roots', () {
    mkdir('lib/features/activities');

    final tree = build(root: 'lib/features');

    expect(tree.name, 'lib/features');
    expect([for (final c in tree.children) c.name], ['activities']);
  });

  test('renderAsciiTree draws connectors and indentation', () {
    mkdir('lib/core');
    mkdir('lib/features/activities');
    mkdir('lib/features/connections');
    mkdir('lib/features/ocr_preview');
    mkdir('lib/features/workflow');
    mkdir('lib/initialization');

    final lines = renderAsciiTree(build());

    expect(lines, [
      'lib',
      '├── core',
      '├── features',
      '│   ├── activities',
      '│   ├── connections',
      '│   ├── ocr_preview',
      '│   └── workflow',
      '└── initialization',
    ]);
  });

  test('renderAsciiTree of an empty root is just the root name', () {
    mkdir('lib');

    expect(renderAsciiTree(build()), ['lib']);
  });
}
