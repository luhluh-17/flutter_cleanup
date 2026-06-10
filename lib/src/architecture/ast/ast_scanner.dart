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

/// Finds JSON-serialization usage under [root] (ARCH109).
///
/// Reports the offset of: `jsonDecode`/`jsonEncode` calls, `fromJson` factory/
/// named constructors, and `toJson` method declarations.
List<int> findJsonSerialization(AstNode root) {
  final visitor = _JsonVisitor();
  root.accept(visitor);
  return visitor.offsets;
}

class _JsonVisitor extends RecursiveAstVisitor<void> {
  final List<int> offsets = [];

  static const _calls = {'jsonDecode', 'jsonEncode'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_calls.contains(node.methodName.name)) offsets.add(node.offset);
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
}
