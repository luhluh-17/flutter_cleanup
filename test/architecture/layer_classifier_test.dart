import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:test/test.dart';

void main() {
  const classifier = LayerClassifier();

  test('classifies feature data/datasources', () {
    final info = classifier
        .classify('lib/features/auth/data/datasources/auth_remote.dart');
    expect(info.layer, Layer.data);
    expect(info.sublayer, Sublayer.datasources);
    expect(info.feature, 'auth');
    expect(info.isDatasource, isTrue);
  });

  test('classifies feature domain/entities', () {
    final info =
        classifier.classify('lib/features/auth/domain/entities/user.dart');
    expect(info.layer, Layer.domain);
    expect(info.isEntity, isTrue);
    expect(info.feature, 'auth');
  });

  test('classifies feature domain/repositories as a contract', () {
    final info = classifier
        .classify('lib/features/auth/domain/repositories/user_repo.dart');
    expect(info.isDomainContract, isTrue);
  });

  test('classifies feature data/repositories as an impl', () {
    final info = classifier
        .classify('lib/features/auth/data/repositories/user_repo_impl.dart');
    expect(info.isRepositoryImpl, isTrue);
    expect(info.layer, Layer.data);
  });

  test('classifies presentation pages and providers', () {
    expect(
      classifier.classify('lib/features/a/presentation/pages/x.dart').isPage,
      isTrue,
    );
    expect(
      classifier
          .classify('lib/features/a/presentation/providers/x.dart')
          .isProvider,
      isTrue,
    );
  });

  test('classifies core and the router directory', () {
    final core = classifier.classify('lib/core/error/failure.dart');
    expect(core.isCore, isTrue);
    expect(core.layer, Layer.core);
    expect(core.isRouterDir, isFalse);

    final router =
        classifier.classify('lib/core/config/router/app_router.dart');
    expect(router.isRouterDir, isTrue);
  });

  test('unrecognized paths are unknown', () {
    expect(classifier.classify('lib/main.dart').layer, Layer.unknown);
    expect(classifier.classify('test/foo_test.dart').layer, Layer.unknown);
  });

  test('feature file outside a layer dir keeps the feature but unknown layer',
      () {
    final info = classifier.classify('lib/features/auth/auth.dart');
    expect(info.feature, 'auth');
    expect(info.layer, Layer.unknown);
  });
}
