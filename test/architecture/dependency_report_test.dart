import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:test/test.dart';

void main() {
  test('renders a sorted feature tree', () {
    final tree = renderDependencyTree({
      'dashboard': ['auth', 'notifications'],
      'auth': ['profile', 'settings'],
    });
    expect(tree, '''
auth
├── profile
└── settings
dashboard
├── auth
└── notifications''');
  });

  test('marks features with no dependencies', () {
    expect(renderDependencyTree({'auth': []}), 'auth (no dependencies)');
  });

  test('handles an empty graph', () {
    expect(renderDependencyTree({}), 'No features found.');
  });
}
