import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_arch_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Writes [files] (relative path → content) plus a pubspec into [tempDir] and
  /// returns its [ProjectPaths]. Parent directories are created as needed.
  ProjectPaths project(Map<String, String> files,
      {String packageName = 'demo'}) {
    File(p.join(tempDir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: $packageName\n');
    files.forEach((rel, content) {
      final file = File(p.join(tempDir.path, p.joinAll(rel.split('/'))));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    return ProjectPaths(tempDir.path);
  }

  Future<ArchitectureResult> analyze(Map<String, String> files) =>
      ArchitectureAnalyzer().analyze(project(files));

  /// The codes present in [result], for concise assertions.
  Set<String> codes(ArchitectureResult result) =>
      result.findings.map((f) => f.rule).toSet();

  Finding findingFor(ArchitectureResult result, String code) =>
      result.findings.firstWhere((f) => f.rule == code);

  group('a clean project', () {
    test('has no violations and scores 100', () async {
      final result = await analyze({
        'lib/features/auth/data/datasources/auth_remote.dart':
            'class AuthRemoteDataSource {}\n',
        'lib/features/auth/data/models/user_model.dart':
            'class UserModel {}\n',
        'lib/features/auth/data/repositories/user_repository_impl.dart':
            "import '../../domain/repositories/user_repository.dart';\n"
                'class UserRepositoryImpl implements UserRepository {}\n',
        'lib/features/auth/domain/entities/user.dart': 'class User {}\n',
        'lib/features/auth/domain/repositories/user_repository.dart':
            'abstract class UserRepository {}\n',
        'lib/features/auth/domain/usecases/login.dart':
            'class LoginUseCase {}\n',
        'lib/features/auth/presentation/pages/login_page.dart':
            'class LoginPage {}\n',
        'lib/features/auth/presentation/providers/auth_provider.dart':
            'class AuthState {}\n',
        'lib/features/auth/presentation/widgets/button.dart':
            'class Button {}\n',
      });

      expect(result.findings, isEmpty);
      expect(result.score, 100);
      expect(result.summary,
          {'layer': 0, 'structure': 0, 'riverpod': 0, 'routing': 0, 'feature': 0});
    });
  });

  group('layer rules', () {
    test('ARCH101: domain must not import infrastructure packages', () async {
      final result = await analyze({
        'lib/features/auth/domain/entities/user.dart':
            "import 'package:dio/dio.dart';\nclass User {}\n",
      });
      expect(codes(result), contains('ARCH101'));
      expect(findingFor(result, 'ARCH101').line, 1);
      expect(findingFor(result, 'ARCH101').confidence, Confidence.high);
    });

    test('ARCH102: entities must not import models', () async {
      final result = await analyze({
        'lib/features/auth/domain/entities/user.dart':
            "import '../../data/models/user_model.dart';\nclass User {}\n",
        'lib/features/auth/data/models/user_model.dart':
            'class UserModel {}\n',
      });
      expect(codes(result), contains('ARCH102'));
    });

    test('ARCH103: presentation must not import datasources', () async {
      final result = await analyze({
        'lib/features/auth/presentation/pages/login_page.dart':
            "import '../../data/datasources/auth_remote.dart';\n"
                'class LoginPage {}\n',
        'lib/features/auth/data/datasources/auth_remote.dart':
            'class AuthRemoteDataSource {}\n',
      });
      expect(codes(result), contains('ARCH103'));
    });

    test('ARCH107/108: presentation must not instantiate Dio/datasources',
        () async {
      final result = await analyze({
        'lib/features/auth/presentation/pages/login_page.dart':
            'class LoginPage {\n'
                '  void f() { final a = Dio(); final b = AuthRemoteDataSource(); }\n'
                '}\n',
      });
      expect(codes(result), containsAll(['ARCH107', 'ARCH108']));
    });

    test('ARCH109: presentation must not contain JSON serialization',
        () async {
      final result = await analyze({
        'lib/features/auth/presentation/pages/login_page.dart':
            'class LoginPage {\n'
                '  Map<String, dynamic> toJson() => {};\n'
                '}\n',
      });
      expect(codes(result), contains('ARCH109'));
    });
  });

  group('structure rules', () {
    test('ARCH201/202/203: a feature missing layers is reported', () async {
      final result = await analyze({
        'lib/features/auth/domain/entities/user.dart': 'class User {}\n',
      });
      expect(codes(result), containsAll(['ARCH201', 'ARCH203']));
      expect(codes(result), isNot(contains('ARCH202')));
    });

    test('ARCH206: a repository impl outside data/repositories', () async {
      final result = await analyze({
        'lib/features/auth/domain/repositories/user_repository.dart':
            'abstract class UserRepository {}\n'
                'class UserRepositoryImpl implements UserRepository {}\n',
      });
      expect(codes(result), contains('ARCH206'));
    });

    test('ARCH209 is always medium confidence', () async {
      final result = await analyze({
        'lib/features/auth/data/repositories/user_repository_impl.dart':
            'class UserRepositoryImpl {}\n',
      });
      expect(codes(result), contains('ARCH209'));
      expect(findingFor(result, 'ARCH209').confidence, Confidence.medium);
    });

    test('ARCH209 does not fire when the impl implements a contract', () async {
      final result = await analyze({
        'lib/features/auth/data/repositories/user_repository_impl.dart':
            "import '../../domain/repositories/user_repository.dart';\n"
                'class UserRepositoryImpl implements UserRepository {}\n',
        'lib/features/auth/domain/repositories/user_repository.dart':
            'abstract class UserRepository {}\n',
      });
      expect(codes(result), isNot(contains('ARCH209')));
    });
  });

  group('routing rules', () {
    test('ARCH402: a feature defines its own GoRouter', () async {
      final result = await analyze({
        'lib/features/auth/presentation/pages/router.dart':
            'class R { final r = GoRouter(); }\n',
      });
      expect(codes(result), contains('ARCH402'));
    });
  });

  group('feature boundary rules', () {
    test('ARCH501 + ARCH502: cross-feature import and cycle', () async {
      final result = await analyze({
        'lib/features/auth/data/repositories/a.dart':
            "import 'package:demo/features/profile/domain/entities/p.dart';\n"
                'class A {}\n',
        'lib/features/profile/data/repositories/b.dart':
            "import 'package:demo/features/auth/domain/entities/u.dart';\n"
                'class B {}\n',
        'lib/features/auth/domain/entities/u.dart': 'class U {}\n',
        'lib/features/profile/domain/entities/p.dart': 'class P {}\n',
        'lib/features/auth/presentation/pages/x.dart': 'class X {}\n',
        'lib/features/profile/presentation/pages/y.dart': 'class Y {}\n',
      });
      expect(codes(result), containsAll(['ARCH501', 'ARCH502']));

      final cycle =
          result.violations.firstWhere((v) => v.code == 'ARCH502');
      expect(cycle.cyclePath.first, cycle.cyclePath.last);
      expect(cycle.cyclePath.toSet(), {'auth', 'profile'});
    });

    test('ARCH503: a feature with too much fan-out', () async {
      final files = <String, String>{};
      final imports = StringBuffer();
      for (final dep in ['a', 'b', 'c', 'd', 'e', 'f']) {
        files['lib/features/$dep/domain/entities/$dep.dart'] =
            'class ${dep.toUpperCase()} {}\n';
        imports.writeln(
            "import 'package:demo/features/$dep/domain/entities/$dep.dart';");
      }
      files['lib/features/hub/data/repositories/hub.dart'] =
          '$imports\nclass Hub {}\n';
      final result = await analyze(files);
      expect(codes(result), contains('ARCH503'));
    });
  });

  group('scoring and mapping', () {
    test('score uses category weights (feature 5 > layer 3)', () async {
      // One ARCH101 (layer, weight 3) only.
      final layerOnly = await analyze({
        'lib/features/auth/domain/entities/user.dart':
            "import 'package:dio/dio.dart';\nclass User {}\n",
        'lib/features/auth/data/models/m.dart': 'class M {}\n',
        'lib/features/auth/presentation/pages/p.dart': 'class P {}\n',
      });
      expect(layerOnly.violationsByCode, containsPair('ARCH101', 1));
      expect(layerOnly.score, 100 - 3);
    });

    test('rich violations are a superset of lean findings', () async {
      final result = await analyze({
        'lib/features/auth/domain/entities/user.dart':
            "import 'package:dio/dio.dart';\nclass User {}\n",
      });
      final v = result.violations.firstWhere((v) => v.code == 'ARCH101');
      expect(v.featureName, 'auth');
      expect(v.layer, Layer.domain);
      // The lean Finding carries only the output-facing subset.
      expect(v.toFinding().rule, 'ARCH101');
      expect(result.findings.length, result.violations.length);
    });
  });
}
