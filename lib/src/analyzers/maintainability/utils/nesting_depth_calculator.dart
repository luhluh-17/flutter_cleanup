import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Estimates the maximum widget-tree nesting depth within a `build()` body.
///
/// This is a deliberately *practical* AST approximation (no element/type
/// resolution): it walks the body and counts how deeply *widget* constructor
/// expressions nest inside one another. Non-widget expressions between widgets
/// (e.g. `EdgeInsets.all(8)`, a `Color`, a callback) do not add depth, so a
/// `Column > Container > Card > Padding > Row > Expanded > Text` tree measures a
/// depth of 7 — matching how a developer reads the tree.
///
/// A widget node is recognized the same way [DuplicateWidgetsAnalyzer] does:
/// - `InstanceCreationExpression` (`const Foo(...)` / `Foo.named(...)`), and
/// - PascalCase call-position identifiers parsed as `MethodInvocation`
///   (`Foo(...)` or `Type.named(...)`), since unresolved constructors look like
///   method calls.
/// A small blocklist drops common Flutter value/config types that are not
/// structural widgets.
class NestingDepthCalculator {
  const NestingDepthCalculator();

  /// PascalCase constructors that are *not* structural widgets — value/config
  /// types that appear inside `build()` and would otherwise inflate depth.
  ///
  /// This intentionally includes the *decoration, constraint and border*
  /// wrappers (`InputDecoration`, `BoxDecoration`, `OutlineInputBorder`, …), not
  /// just the leaf values they hold (`EdgeInsets`, `TextStyle`, `Border`). Those
  /// wrappers are passed to named parameters like `decoration:`/`constraints:`;
  /// counting them inflated the reported depth by one per config object (a
  /// labeled `TextField` read as depth 6, a decorated `Container` as depth 7),
  /// which pushed idiomatic leaf widgets over the threshold. A blocklist is
  /// inherently incomplete — new config types (e.g. `WidgetStateProperty`) will
  /// re-inflate depth until added here.
  static const Set<String> _nonWidgetBlocklist = {
    // Leaf value types.
    'EdgeInsets',
    'EdgeInsetsDirectional',
    'Duration',
    'Color',
    'Colors',
    'Offset',
    'Size',
    'TextStyle',
    'Radius',
    'Key',
    'ValueKey',
    'GlobalKey',
    // Decorations & constraints (hold the leaf value types above).
    'InputDecoration',
    'BoxDecoration',
    'ShapeDecoration',
    'BoxConstraints',
    'BoxShadow',
    // Borders.
    'Border',
    'BorderSide',
    'BorderRadius',
    'InputBorder',
    'OutlineInputBorder',
    'UnderlineInputBorder',
    // ShapeBorder subtypes (used in `shape:` on Card, Dialog, buttons, …).
    'RoundedRectangleBorder',
    'CircleBorder',
    'StadiumBorder',
    'BeveledRectangleBorder',
    'ContinuousRectangleBorder',
    // Gradients.
    'LinearGradient',
    'RadialGradient',
    'SweepGradient',
  };

  /// `Type.method(...)` calls whose method is a known *lookup* (returns an
  /// ambient value rather than building a widget), so the leading `Type` is not
  /// a widget constructor.
  static const Set<String> _nonConstructorMethods = {'of', 'maybeOf'};

  /// Returns the deepest widget nesting found anywhere in [body], or 0 if the
  /// body contains no recognized widgets.
  int maxDepth(AstNode body) {
    final visitor = _DepthVisitor();
    body.accept(visitor);
    return visitor.maxDepth;
  }

  static bool _isWidgetName(String name) =>
      name.isNotEmpty &&
      RegExp(r'^[A-Z]').hasMatch(name) &&
      !_nonWidgetBlocklist.contains(name);
}

/// Tracks depth with enter/exit semantics: increment on entering a widget node,
/// record the running maximum, recurse into children, then decrement.
class _DepthVisitor extends RecursiveAstVisitor<void> {
  int _current = 0;
  int maxDepth = 0;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    final name = type.importPrefix?.name.lexeme ?? type.name.lexeme;
    _enterIfWidget(name, () => super.visitInstanceCreationExpression(node));
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final method = node.methodName.name;
    String? widgetName;
    if (target == null) {
      if (NestingDepthCalculator._isWidgetName(method)) widgetName = method;
    } else if (target is SimpleIdentifier &&
        NestingDepthCalculator._isWidgetName(target.name) &&
        !RegExp(r'^[A-Z]').hasMatch(method) &&
        !NestingDepthCalculator._nonConstructorMethods.contains(method)) {
      // `Type.named(...)` — a named constructor like `ListView.builder`.
      widgetName = target.name;
    }

    if (widgetName != null) {
      _enterIfWidget(widgetName, () => super.visitMethodInvocation(node));
    } else {
      super.visitMethodInvocation(node);
    }
  }

  /// Runs [visitChildren] with the depth incremented (recording the max), then
  /// restores it. [name] is already known to be a widget by the callers.
  void _enterIfWidget(String name, void Function() visitChildren) {
    _current++;
    if (_current > maxDepth) maxDepth = _current;
    visitChildren();
    _current--;
  }
}
