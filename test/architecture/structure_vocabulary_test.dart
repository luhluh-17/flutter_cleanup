import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_vocab_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProjectPaths project(Map<String, String> files) {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: demo\n');
    files.forEach((rel, content) {
      final file = File(p.join(tempDir.path, p.joinAll(rel.split('/'))));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    return ProjectPaths(tempDir.path);
  }

  Future<ArchitectureResult> analyze(Map<String, String> files) =>
      ArchitectureAnalyzer().analyze(project(files));

  List<Finding> findingsFor(ArchitectureResult result, String code) =>
      result.findings.where((f) => f.rule == code).toList();

  group('ARCH210 — unrecognized feature folders', () {
    test('flags a non-layer folder once, not per file', () async {
      final result = await analyze({
        'lib/features/exec/infrastructure/runtime/runtime.dart': 'class A {}\n',
        'lib/features/exec/infrastructure/runtime/state.dart': 'class B {}\n',
        'lib/features/exec/infrastructure/providers/p.dart': 'class C {}\n',
      });

      final findings = findingsFor(result, 'ARCH210');
      expect(findings, hasLength(1));
      expect(findings.single.message,
          contains('lib/features/exec/infrastructure'));
      expect(findings.single.path,
          'lib/features/exec/infrastructure/providers/p.dart');
    });

    test('flags each unrecognized folder separately', () async {
      final result = await analyze({
        'lib/features/settings/infrastructure/repo.dart': 'class A {}\n',
        'lib/features/settings/state/s.dart': 'class B {}\n',
      });

      expect(
        findingsFor(result, 'ARCH210').map((f) => f.message).join(' '),
        allOf(contains('lib/features/settings/infrastructure'),
            contains('lib/features/settings/state')),
      );
    });

    test('flags a loose file directly under the feature root', () async {
      final result = await analyze({
        'lib/features/auth/auth.dart': 'class Auth {}\n',
      });

      final findings = findingsFor(result, 'ARCH210');
      expect(findings, hasLength(1));
      expect(findings.single.path, 'lib/features/auth/auth.dart');
      expect(findings.single.message, contains('outside any layer folder'));
    });

    test('does not flag the recognized layer folders', () async {
      final result = await analyze({
        'lib/features/auth/data/models/m_model.dart': 'class MModel {}\n',
        'lib/features/auth/domain/entities/e.dart': 'class E {}\n',
        'lib/features/auth/application/services/s.dart': 'class S {}\n',
        'lib/features/auth/presentation/widgets/w.dart': 'class W {}\n',
      });

      expect(findingsFor(result, 'ARCH210'), isEmpty);
    });
  });

  group('ARCH211 — unrecognized layer sub-folders', () {
    test('flags vocabulary from the wrong layer (domain/models)', () async {
      final result = await analyze({
        'lib/features/ocr/domain/models/box.dart': 'class Box {}\n',
      });

      final findings = findingsFor(result, 'ARCH211');
      expect(findings, hasLength(1));
      expect(findings.single.message,
          contains('lib/features/ocr/domain/models'));
      expect(findings.single.message, contains('entities/'));
      expect(findings.single.message, contains('misleading'));
      expect(findings.single.message,
          contains('"models" is the data layer\'s vocabulary'));
    });

    test('flags synonyms like presentation/screens', () async {
      final result = await analyze({
        'lib/features/auth/presentation/screens/s.dart': 'class S {}\n',
        'lib/features/auth/presentation/controllers/c.dart': 'class C {}\n',
      });

      expect(findingsFor(result, 'ARCH211'), hasLength(2));
    });

    test('flags an unrecognized application sub-folder', () async {
      final result = await analyze({
        'lib/features/exec/application/runtime/r.dart': 'class R {}\n',
      });

      final findings = findingsFor(result, 'ARCH211');
      expect(findings, hasLength(1));
      expect(findings.single.message,
          contains('lib/features/exec/application/runtime'));
      expect(findings.single.message,
          allOf(contains('services'), contains('coordinators'),
              contains('facades')));
    });

    test('flags vocabulary from another layer (application/providers)',
        () async {
      final result = await analyze({
        'lib/features/exec/application/providers/p.dart': 'class P {}\n',
      });

      final findings = findingsFor(result, 'ARCH211');
      expect(findings, hasLength(1));
      expect(findings.single.message,
          contains('"providers" is the presentation layer\'s vocabulary'));
    });

    test('allows the application vocabulary sub-folders', () async {
      final result = await analyze({
        'lib/features/exec/application/services/s.dart': 'class S {}\n',
        'lib/features/exec/application/coordinators/c.dart': 'class C {}\n',
        'lib/features/exec/application/facades/f.dart': 'class F {}\n',
      });

      expect(findingsFor(result, 'ARCH211'), isEmpty);
    });

    test('allows organizational folders under a recognized sub-folder',
        () async {
      final result = await analyze({
        'lib/features/auth/presentation/widgets/fields/f.dart': 'class F {}\n',
        'lib/features/auth/data/repositories/local/r.dart': 'class R {}\n',
      });

      expect(findingsFor(result, 'ARCH211'), isEmpty);
    });

    test('allows loose files directly under a layer', () async {
      final result = await analyze({
        'lib/features/auth/domain/auth_service.dart': 'class AuthService {}\n',
      });

      expect(findingsFor(result, 'ARCH211'), isEmpty);
    });
  });

  group('ARCH212 — unrecognized top-level folders', () {
    test('flags lib folders other than core/ and features/', () async {
      final result = await analyze({
        'lib/routing/router.dart': 'class R {}\n',
        'lib/initialization/init.dart': 'class I {}\n',
      });

      expect(
        findingsFor(result, 'ARCH212').map((f) => f.message).join(' '),
        allOf(contains('lib/routing'), contains('lib/initialization')),
      );
    });

    test('allows loose files under lib/ and anything under core/', () async {
      final result = await analyze({
        'lib/main.dart': 'void main() {}\n',
        'lib/app.dart': 'class App {}\n',
        'lib/core/theme/colors.dart': 'class AppColors {}\n',
      });

      expect(findingsFor(result, 'ARCH212'), isEmpty);
    });
  });

  test('a fully conventional project raises no vocabulary findings', () async {
    final result = await analyze({
      'lib/main.dart': 'void main() {}\n',
      'lib/core/widgets/button.dart': 'class Button {}\n',
      'lib/features/auth/data/datasources/remote.dart':
          'class AuthRemoteDataSource {}\n',
      'lib/features/auth/data/models/user_model.dart': 'class UserModel {}\n',
      'lib/features/auth/data/repositories/user_repository_impl.dart':
          "import '../../domain/repositories/user_repository.dart';\n"
              'class UserRepositoryImpl implements UserRepository {}\n',
      'lib/features/auth/domain/entities/user.dart': 'class User {}\n',
      'lib/features/auth/domain/repositories/user_repository.dart':
          'abstract class UserRepository {}\n',
      'lib/features/auth/domain/usecases/login.dart': 'class LoginUseCase {}\n',
      'lib/features/auth/application/services/auth_service.dart':
          'class AuthService {}\n',
      'lib/features/auth/application/coordinators/auth_coordinator.dart':
          'class AuthCoordinator {}\n',
      'lib/features/auth/presentation/pages/login_page.dart':
          'class LoginPage {}\n',
      'lib/features/auth/presentation/providers/auth_provider.dart':
          'class AuthState {}\n',
      'lib/features/auth/presentation/widgets/button.dart': 'class Button {}\n',
    });

    expect(
      result.findings.where((f) =>
          f.rule == 'ARCH210' || f.rule == 'ARCH211' || f.rule == 'ARCH212'),
      isEmpty,
    );
    expect(result.score, 100);
  });
}
