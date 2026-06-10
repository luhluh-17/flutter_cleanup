import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:test/test.dart';

void main() {
  const def = CleanArchitectureDefinition();

  group('canImport matrix', () {
    test('presentation may import domain, not data', () {
      expect(def.canImport(Layer.presentation, Layer.domain), isTrue);
      expect(def.canImport(Layer.presentation, Layer.data), isFalse);
    });

    test('data may import domain, not presentation', () {
      expect(def.canImport(Layer.data, Layer.domain), isTrue);
      expect(def.canImport(Layer.data, Layer.presentation), isFalse);
    });

    test('domain may import nothing outward', () {
      expect(def.canImport(Layer.domain, Layer.data), isFalse);
      expect(def.canImport(Layer.domain, Layer.presentation), isFalse);
    });

    test('anyone may import core, and same-layer is fine', () {
      expect(def.canImport(Layer.domain, Layer.core), isTrue);
      expect(def.canImport(Layer.presentation, Layer.core), isTrue);
      expect(def.canImport(Layer.data, Layer.data), isTrue);
    });
  });

  group('isForbiddenInDomain', () {
    test('rejects the listed infrastructure packages', () {
      for (final pkg in const [
        'flutter',
        'dio',
        'retrofit',
        'hive',
        'drift',
        'shared_preferences',
      ]) {
        expect(def.isForbiddenInDomain(pkg), isTrue, reason: pkg);
      }
    });

    test('rejects any firebase_* package', () {
      expect(def.isForbiddenInDomain('firebase_core'), isTrue);
      expect(def.isForbiddenInDomain('firebase_auth'), isTrue);
    });

    test('allows ordinary pure packages', () {
      expect(def.isForbiddenInDomain('equatable'), isFalse);
      expect(def.isForbiddenInDomain('meta'), isFalse);
    });
  });
}
