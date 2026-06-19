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

/// A typed-model JSON serialization site found in the AST (ARCH109).
class JsonUsage {
  const JsonUsage(this.offset, {required this.isDeclaration});

  /// AST offset of the site, for line/column lookup.
  final int offset;

  /// Whether a serializable model is *declared* here (a `toJson`/`fromJson`
  /// member or `@JsonSerializable`) rather than *called*.
  ///
  /// A declaration is an unambiguous "model defined in the UI", so callers grade
  /// it high confidence. A call (`obj.toJson()` / `Model.fromJson(...)`) is
  /// ambiguous — a raw-JSON editor or a serialize-at-the-boundary call looks
  /// identical from the AST — so callers grade it lower.
  final bool isDeclaration;
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
///
/// Each site carries [JsonUsage.isDeclaration] so the rule can grade a declared
/// model (certain) above a serialization call (ambiguous).
List<JsonUsage> findJsonSerialization(AstNode root) {
  final visitor = _JsonVisitor();
  root.accept(visitor);
  return visitor.found;
}

class _JsonVisitor extends RecursiveAstVisitor<void> {
  final List<JsonUsage> found = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target;
    // `obj.toJson()` — serializing a typed object.
    if (method == 'toJson' && target != null) {
      found.add(JsonUsage(node.offset, isDeclaration: false));
    } else if (method == 'fromJson' &&
        target is SimpleIdentifier &&
        isPascalCase(target.name)) {
      // `Model.fromJson(...)` — deserializing into a typed model.
      found.add(JsonUsage(node.offset, isDeclaration: false));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'toJson') {
      found.add(JsonUsage(node.offset, isDeclaration: true));
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.name?.lexeme == 'fromJson') {
      found.add(JsonUsage(node.offset, isDeclaration: true));
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    if (node.name.name == 'JsonSerializable') {
      found.add(JsonUsage(node.offset, isDeclaration: true));
    }
    super.visitAnnotation(node);
  }
}
