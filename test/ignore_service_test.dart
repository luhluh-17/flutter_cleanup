import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ignore_service_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void writeConfig(String contents) {
    File(p.join(tempDir.path, IgnoreService.configFileName))
        .writeAsStringSync(contents);
  }

  IgnoreService forProject() => IgnoreService.forProject(tempDir.path);

  group('config loading', () {
    test('missing config file applies only defaults, no throw', () {
      final ignore = forProject();
      expect(ignore.isIgnored('lib/feature.dart'), isFalse);
      // A default still applies.
      expect(ignore.isIgnored('lib/feature.g.dart'), isTrue);
    });

    test('empty config file keeps defaults active', () {
      writeConfig('');
      final ignore = forProject();
      expect(ignore.isIgnored('lib/feature.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/feature.dart'), isFalse);
    });

    test('config without an ignore key keeps defaults active', () {
      // A future, unrelated section must be tolerated, not error.
      writeConfig('duplicate_code:\n  threshold: 0.85\n');
      final ignore = forProject();
      expect(ignore.isIgnored('lib/feature.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/feature.dart'), isFalse);
    });

    test('single user pattern is honored alongside defaults', () {
      writeConfig('ignore:\n  - "lib/legacy/**"\n');
      final ignore = forProject();
      expect(ignore.isIgnored('lib/legacy/old.dart'), isTrue);
      expect(ignore.isIgnored('lib/feature.dart'), isFalse);
      // User patterns add to defaults, they don't replace them.
      expect(ignore.isIgnored('lib/feature.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/grpc/feature.pbjson.dart'), isTrue);
    });

    test('multiple user patterns each match', () {
      writeConfig('''
ignore:
  - "lib/generated/**"
  - "assets/legacy/**"
''');
      final ignore = forProject();
      expect(ignore.isIgnored('lib/generated/api.dart'), isTrue);
      expect(ignore.isIgnored('assets/legacy/logo.png'), isTrue);
      expect(ignore.isIgnored('lib/feature.dart'), isFalse);
    });
  });

  group('built-in defaults', () {
    test('generated and tooling files are ignored without config', () {
      final ignore = forProject();
      expect(ignore.isIgnored('lib/models/user.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/models/user.freezed.dart'), isTrue);
      expect(ignore.isIgnored('test/service.mocks.dart'), isTrue);
      expect(ignore.isIgnored('lib/router.gr.dart'), isTrue);
      expect(ignore.isIgnored('.flutter-plugins'), isTrue);
      expect(ignore.isIgnored('.flutter-plugins-dependencies'), isTrue);
      // A hand-written file is not ignored.
      expect(ignore.isIgnored('lib/models/user.dart'), isFalse);
    });

    test('generated protobuf artifacts are ignored without config', () {
      final ignore = forProject();
      expect(ignore.isIgnored('lib/grpc/activity.pb.dart'), isTrue);
      expect(ignore.isIgnored('lib/grpc/activity.pbgrpc.dart'), isTrue);
      expect(ignore.isIgnored('lib/grpc/activity.pbjson.dart'), isTrue);
      expect(ignore.isIgnored('lib/grpc/activity.pbenum.dart'), isTrue);
      // Nested under any depth, matching how protoc lays out generated dirs.
      expect(
        ignore.isIgnored('lib/core/grpc/generated/abenflow/v1/common.pbjson.dart'),
        isTrue,
      );
      // A hand-written file that merely sits beside them is not ignored.
      expect(ignore.isIgnored('lib/grpc/activity_service.dart'), isFalse);
    });

    test('defaultIgnorePatterns documents the exact built-in set', () {
      expect(IgnoreService.defaultIgnorePatterns, [
        '**/*.g.dart',
        '**/*.freezed.dart',
        '**/*.mocks.dart',
        '**/*.gr.dart',
        '**/*.pb.dart',
        '**/*.pbgrpc.dart',
        '**/*.pbjson.dart',
        '**/*.pbenum.dart',
        '.flutter-plugins',
        '.flutter-plugins-dependencies',
      ]);
    });
  });

  group('glob semantics', () {
    test('"**/*.g.dart" matches at nested depths under lib/', () {
      final ignore = IgnoreService(['**/*.g.dart']);
      expect(ignore.isIgnored('lib/a/b/c/deep.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/shallow.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/shallow.dart'), isFalse);
    });

    test('trailing "/**" matches both direct children and deep descendants',
        () {
      // Glob implementations vary around trailing /**; pin the behavior.
      final ignore = IgnoreService(['lib/generated/**']);
      expect(ignore.isIgnored('lib/generated/foo.g.dart'), isTrue);
      expect(ignore.isIgnored('lib/generated/bar.dart'), isTrue);
      expect(ignore.isIgnored('lib/generated/sub/deep.dart'), isTrue);
      expect(ignore.isIgnored('lib/other/bar.dart'), isFalse);
    });

    test('matching is POSIX-keyed regardless of host platform', () {
      // Inputs are project-relative POSIX paths (forward slashes), as produced
      // by toPosixRelative. The same key matches on every OS; a backslash-style
      // string is not a POSIX path and must not match.
      final ignore = IgnoreService(['lib/generated/**']);
      expect(ignore.isIgnored('lib/generated/api.dart'), isTrue);
      expect(ignore.isIgnored(r'lib\generated\api.dart'), isFalse);
    });
  });
}
