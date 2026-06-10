import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/path_utils.dart';
import 'ignore_service.dart';

/// A single directory in a [DirectoryTreeBuilder] result.
///
/// [name] is the directory's base name for nested nodes; for the root node it
/// is the project-relative POSIX path of the tree root (e.g. `lib` or
/// `lib/features`). [children] are sorted alphabetically by name.
class DirectoryTreeNode {
  const DirectoryTreeNode({required this.name, this.children = const []});

  /// Directory name (base name for children, project-relative for the root).
  final String name;

  /// Child directories, sorted alphabetically.
  final List<DirectoryTreeNode> children;

  /// Serializes this node (recursively) for the `tree --json` contract.
  Map<String, dynamic> toJson() => {
        'name': name,
        'children': [for (final child in children) child.toJson()],
      };
}

/// Builds a directory-only tree of a project subfolder.
///
/// Walks the file system under a root directory and returns a
/// [DirectoryTreeNode] hierarchy containing **directories only** — files are
/// intentionally excluded. Children are sorted alphabetically so output is
/// stable across platforms and file-system enumeration orders.
///
/// Directories whose project-relative POSIX path matches an [IgnoreService]
/// pattern are pruned, along with their entire subtree. To exclude a
/// directory, use a pattern that matches the directory path itself, e.g.
/// `lib/generated` or `**/generated`.
///
/// This service does no printing and no AST analysis; it only reads the
/// directory structure.
class DirectoryTreeBuilder {
  const DirectoryTreeBuilder();

  /// Builds the tree rooted at [rootDir] (an absolute path inside the project
  /// rooted at [projectRoot]).
  ///
  /// [maxDepth] limits how many levels below the root are included: `1` keeps
  /// only the root's immediate children, `null` means unlimited.
  DirectoryTreeNode build({
    required String projectRoot,
    required String rootDir,
    required IgnoreService ignoreService,
    int? maxDepth,
  }) {
    final rootName = toPosixRelative(projectRoot, rootDir);
    return DirectoryTreeNode(
      name: rootName == '.' ? p.basename(rootDir) : rootName,
      children: _children(
        projectRoot: projectRoot,
        dir: rootDir,
        ignoreService: ignoreService,
        maxDepth: maxDepth,
        depth: 1,
      ),
    );
  }

  List<DirectoryTreeNode> _children({
    required String projectRoot,
    required String dir,
    required IgnoreService ignoreService,
    required int? maxDepth,
    required int depth,
  }) {
    if (maxDepth != null && depth > maxDepth) return const [];

    final subdirs = Directory(dir)
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((d) =>
            !ignoreService.isIgnored(toPosixRelative(projectRoot, d.path)))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    return [
      for (final subdir in subdirs)
        DirectoryTreeNode(
          name: p.basename(subdir.path),
          children: _children(
            projectRoot: projectRoot,
            dir: subdir.path,
            ignoreService: ignoreService,
            maxDepth: maxDepth,
            depth: depth + 1,
          ),
        ),
    ];
  }
}

/// Renders [root] as ASCII-tree lines:
///
/// ```text
/// lib
/// ├── core
/// └── features
///     └── activities
/// ```
List<String> renderAsciiTree(DirectoryTreeNode root) {
  final lines = <String>[root.name];

  void walk(DirectoryTreeNode node, String prefix) {
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final isLast = i == node.children.length - 1;
      lines.add('$prefix${isLast ? '└── ' : '├── '}${child.name}');
      walk(child, '$prefix${isLast ? '    ' : '│   '}');
    }
  }

  walk(root, '');
  return lines;
}
