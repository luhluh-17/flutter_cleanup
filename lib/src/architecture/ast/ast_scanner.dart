import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A constructor-like call discovered in the AST: `Foo(...)`, `const Foo(...)`,
/// or `Foo.named(...)`.
class Instantiation {
  const Instantiation(this.typeName, this.offset);

  /// The type being constructed (`Dio`, `UserRepositoryImpl`, …).
  final String typeName;

  /// AST offset of the call, for line/column lookup.
  final int offset;
}

/// Finds every constructor-like call under [root].
///
/// Because flutter_cleanup parses *without* element resolution, an unprefixed
/// `Foo()` parses as a [MethodInvocation], not an [InstanceCreationExpression];
/// both are collected, with PascalCase used as the heuristic for "this is a type
/// construction". This mirrors the approach already proven in the duplicate-widget
/// analyzer.
List<Instantiation> findInstantiations(AstNode root) {
  final visitor = _InstantiationVisitor();
  root.accept(visitor);
  return visitor.found;
}

/// Whether [name] looks like a type name (starts with an uppercase letter).
bool isPascalCase(String name) =>
    name.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(name);

class _InstantiationVisitor extends RecursiveAstVisitor<void> {
  final List<Instantiation> found = [];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    final name = type.importPrefix?.name.lexeme ?? type.name.lexeme;
    found.add(Instantiation(name, node.offset));
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final method = node.methodName.name;
    if (target == null) {
      // Unprefixed `Foo(...)` — a constructor call without `new`/`const`.
      if (isPascalCase(method)) found.add(Instantiation(method, node.offset));
    } else if (target is SimpleIdentifier &&
        isPascalCase(target.name) &&
        !isPascalCase(method)) {
      // `Type.named(...)` — record the type, not the constructor name.
      found.add(Instantiation(target.name, node.offset));
    }
    super.visitMethodInvocation(node);
  }
}

/// Finds *typed-model* JSON serialization under [root] (ARCH109).
///
/// The boundary this guards is "domain/DTO (de)serialization shouldn't live in
/// the UI", so it deliberately targets only the signals of a *typed model*:
/// - declaring a serializable model in presentation — a `toJson` method or a
///   `fromJson` constructor declaration, or a `@JsonSerializable` annotation;
/// - (de)serializing a typed object — a `x.toJson()` invocation or a
///   `Type.fromJson(...)` call (e.g. `jsonEncode(workflow.toJson())`).
///
/// It intentionally does *not* flag bare `jsonEncode`/`jsonDecode` over opaque
/// `String`/`Object?` payloads: pretty-printing a blob for a viewer or parsing a
/// raw-edit field is legitimate UI work with no model to route through a mapper.
List<int> findJsonSerialization(AstNode root) {
  final visitor = _JsonVisitor();
  root.accept(visitor);
  return visitor.offsets;
}

class _JsonVisitor extends RecursiveAstVisitor<void> {
  final List<int> offsets = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target;
    // `obj.toJson()` — serializing a typed object.
    if (method == 'toJson' && target != null) {
      offsets.add(node.offset);
    } else if (method == 'fromJson' &&
        target is SimpleIdentifier &&
        isPascalCase(target.name)) {
      // `Model.fromJson(...)` — deserializing into a typed model.
      offsets.add(node.offset);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'toJson') offsets.add(node.offset);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.name?.lexeme == 'fromJson') offsets.add(node.offset);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    if (node.name.name == 'JsonSerializable') offsets.add(node.offset);
    super.visitAnnotation(node);
  }
}
