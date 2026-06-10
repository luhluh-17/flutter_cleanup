import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import 'definition/architecture_definition.dart';
import 'definition/layer_info.dart';

/// A single `import`/`export` directive, resolved and classified.
class ResolvedImport {
  const ResolvedImport({
    required this.rawUri,
    required this.line,
    required this.isInternal,
    this.packageName,
    this.targetRelPath,
    this.targetLayer,
  });

  /// The literal URI string from the directive (e.g. `package:dio/dio.dart`).
  final String rawUri;

  /// 1-based line of the directive, for diagnostics.
  final int line;

  /// Whether the target resolves to a file inside this project's `lib/`.
  final bool isInternal;

  /// For external imports, the `<name>` in `package:<name>/…` (or `dart` for
  /// `dart:` URIs). Null for internal imports.
  final String? packageName;

  /// For internal imports, the resolved project-relative POSIX path.
  final String? targetRelPath;

  /// For internal imports, the [LayerInfo] of [targetRelPath].
  final LayerInfo? targetLayer;
}

/// Resolves the `import`/`export` directives of a compilation unit into
/// [ResolvedImport]s, classifying each as external (a pub package) or internal
/// (another file in this project's `lib/`).
///
/// Resolution is purely lexical — relative URIs are joined against the importing
/// file's directory and `package:<self>/x` maps to `lib/x` — so no filesystem
/// access or element resolution is required.
class ImportResolver {
  ImportResolver({
    required this.packageName,
    required this.definition,
  });

  /// This project's own package name (from `pubspec.yaml`), used to recognize
  /// `package:<self>/…` self-imports as internal.
  final String packageName;

  final ArchitectureDefinition definition;

  /// Resolves every directive in [unit]. [importerRelPath] is the importing
  /// file's project-relative POSIX path; [lineInfo] maps offsets to lines.
  List<ResolvedImport> resolve(
    CompilationUnit unit,
    String importerRelPath,
    LineInfo lineInfo,
  ) {
    final result = <ResolvedImport>[];
    for (final directive in unit.directives) {
      if (directive is! UriBasedDirective) continue;
      // Only import/export carry dependency meaning here (skip `part`/`library`).
      if (directive is! ImportDirective && directive is! ExportDirective) {
        continue;
      }
      final uri = directive.uri.stringValue;
      if (uri == null) continue; // interpolated/unparsable URI
      final line = lineInfo.getLocation(directive.offset).lineNumber;
      result.add(_resolve(uri, importerRelPath, line));
    }
    return result;
  }

  ResolvedImport _resolve(String uri, String importerRelPath, int line) {
    if (uri.startsWith('dart:')) {
      return ResolvedImport(
        rawUri: uri,
        line: line,
        isInternal: false,
        packageName: 'dart',
      );
    }

    if (uri.startsWith('package:')) {
      final withoutScheme = uri.substring('package:'.length);
      final slash = withoutScheme.indexOf('/');
      final name =
          slash == -1 ? withoutScheme : withoutScheme.substring(0, slash);
      if (name == packageName && slash != -1) {
        // package:<self>/foo/bar.dart -> lib/foo/bar.dart
        final rel = 'lib/${withoutScheme.substring(slash + 1)}';
        return _internal(uri, line, rel);
      }
      return ResolvedImport(
        rawUri: uri,
        line: line,
        isInternal: false,
        packageName: name,
      );
    }

    // Relative URI: resolve against the importing file's directory.
    final dir = p.posix.dirname(importerRelPath);
    final rel = p.posix.normalize(p.posix.join(dir, uri));
    return _internal(uri, line, rel);
  }

  ResolvedImport _internal(String uri, int line, String targetRelPath) {
    return ResolvedImport(
      rawUri: uri,
      line: line,
      isInternal: true,
      targetRelPath: targetRelPath,
      targetLayer: definition.classify(targetRelPath),
    );
  }
}
