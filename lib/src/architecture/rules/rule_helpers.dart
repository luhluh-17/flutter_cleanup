import 'package:analyzer/dart/ast/ast.dart';

import '../definition/layer.dart';
import '../definition/layer_info.dart';

/// Human-readable `layer/sublayer` label for a target, used in messages.
String layerLabel(LayerInfo info) {
  if (info.isCore) return 'core';
  final layer = info.layer == Layer.unknown ? 'unknown' : info.layer.name;
  if (info.sublayer == Sublayer.none) return layer;
  return '$layer/${info.sublayer.name}';
}

/// Whether [typeName] names a data source (e.g. `UserRemoteDataSource`).
bool isDatasourceType(String typeName) =>
    typeName.contains('DataSource') || typeName.contains('Datasource');

/// Whether [typeName] names a repository (contract or impl).
bool isRepositoryType(String typeName) =>
    typeName.endsWith('Repository') || typeName.endsWith('RepositoryImpl');

/// Whether [typeName] names a repository *implementation*.
bool isRepositoryImplType(String typeName) => typeName.endsWith('RepositoryImpl');

/// The top-level class declarations of [unit].
Iterable<ClassDeclaration> classDeclarations(CompilationUnit unit) sync* {
  for (final declaration in unit.declarations) {
    if (declaration is ClassDeclaration) yield declaration;
  }
}

/// The declared name of [cls]. Uses `namePart.typeName`, the access path this
/// analyzer version exposes (mirrors the duplicate-widget analyzer).
String className(ClassDeclaration cls) => cls.namePart.typeName.lexeme;

/// Whether [cls] is declared `abstract`.
bool isAbstractClass(ClassDeclaration cls) => cls.abstractKeyword != null;

/// The superclass name in an `extends` clause, or null.
String? superclassName(ClassDeclaration cls) =>
    cls.extendsClause?.superclass.name.lexeme;

/// The interface names in an `implements` clause.
List<String> implementsNames(ClassDeclaration cls) => [
      for (final type in cls.implementsClause?.interfaces ?? const [])
        type.name.lexeme,
    ];
