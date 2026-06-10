import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import 'definition/layer_info.dart';
import 'import_resolver.dart';

/// Everything the rules need to know about one parsed Dart file under `lib/`.
///
/// Built once per file during context creation (parse-once), then shared by
/// every rule — so no rule re-reads or re-parses source.
class DartFileInfo {
  const DartFileInfo({
    required this.relPath,
    required this.layer,
    required this.unit,
    required this.lineInfo,
    required this.imports,
  });

  /// Project-relative POSIX path.
  final String relPath;

  /// Where this file sits in the architecture.
  final LayerInfo layer;

  /// The parsed (unresolved) AST.
  final CompilationUnit unit;

  /// Offset→line/column mapping for [unit].
  final LineInfo lineInfo;

  /// This file's resolved import/export directives.
  final List<ResolvedImport> imports;

  /// 1-based line for an AST [offset] within this file.
  int lineAt(int offset) => lineInfo.getLocation(offset).lineNumber;

  /// 1-based column for an AST [offset] within this file.
  int columnAt(int offset) => lineInfo.getLocation(offset).columnNumber;
}
