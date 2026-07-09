import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('primary_ctors_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- Fixture helpers -------------------------------------------------------

  void writePubspec() {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
  }

  /// Writes a Dart file at [relUnderLib] (relative to `lib/`).
  void writeDart(String relUnderLib, String contents) {
    final file =
        File(p.join(tempDir.path, 'lib', p.joinAll(relUnderLib.split('/'))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void writeConfig(String contents) {
    File(p.join(tempDir.path, '.flutter_cleanup.yaml'))
        .writeAsStringSync(contents);
  }

  Future<AnalysisResult> run() =>
      const PrimaryConstructorsAnalyzer().analyze(ProjectPaths(tempDir.path));

  Future<List<Finding>> findings() async => (await run()).findings;

  // --- Positive candidate ----------------------------------------------------

  group('safe candidates', () {
    test('a boilerplate widget is reported once', () async {
      writePubspec();
      writeDart('widgets/primary_button.dart', '''
import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Text(label);
}
''');

      final result = await findings();
      expect(result, hasLength(1));
      final finding = result.single;
      expect(finding.rule, 'primary_constructor');
      expect(finding.severity, Severity.info);
      expect(finding.message, contains('"PrimaryButton"'));
      expect(finding.recommendation, isNotNull);
      expect(finding.line, isNotNull);
    });

    test('a plain data class with a body-less ctor is reported', () async {
      writePubspec();
      writeDart('models/point.dart', '''
class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;
}
''');

      final result = await findings();
      expect(result, hasLength(1));
      expect(result.single.message, contains('"Point"'));
    });

    test('an empty constructor block body is still a candidate', () async {
      writePubspec();
      writeDart('models/box.dart', '''
class Box {
  Box(this.value) {}

  final int value;
}
''');

      expect(await findings(), hasLength(1));
    });
  });

  // --- Unsafe situations (each must NOT be reported) -------------------------

  group('unsafe situations are not reported', () {
    Future<void> expectNoFindings(String file, String source) async {
      writePubspec();
      writeDart(file, source);
      expect(await findings(), isEmpty);
    }

    test('field with a documentation comment (required-drop risk)', () async {
      await expectNoFindings('a.dart', '''
class A {
  const A({required this.value});

  /// The value.
  final String value;
}
''');
    });

    test('field with an annotation', () async {
      await expectNoFindings('a.dart', '''
class A {
  const A({required this.value});

  @Deprecated('x')
  final String value;
}
''');
    });

    test('field without an explicit type', () async {
      await expectNoFindings('a.dart', '''
class A {
  A(this.value);

  final value = 0;
}
''');
    });

    test('non-final field', () async {
      await expectNoFindings('a.dart', '''
class A {
  A(this.value);

  int value;
}
''');
    });

    test('late field', () async {
      await expectNoFindings('a.dart', '''
class A {
  A(this.value);

  late final int value;
}
''');
    });

    test('constructor body that initializes a field', () async {
      await expectNoFindings('a.dart', '''
class A {
  A(this.value) {
    print(value);
  }

  final int value;
}
''');
    });

    test('two constructors', () async {
      await expectNoFindings('a.dart', '''
class A {
  const A(this.value);
  const A.zero() : this(0);

  final int value;
}
''');
    });

    test('factory constructor', () async {
      await expectNoFindings('a.dart', '''
class A {
  factory A(int v) => A._(v);
  A._(this.value);

  final int value;
}
''');
    });

    test('named super initializer', () async {
      await expectNoFindings('a.dart', '''
class Base {
  const Base({Object? key});
}

class A extends Base {
  const A({required this.value, Object? key}) : super(key: key);

  final int value;
}
''');
    });

    test('a constructor with only super.key (no this. formal)', () async {
      await expectNoFindings('a.dart', '''
import 'package:flutter/material.dart';

class A extends StatelessWidget {
  const A({super.key});

  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');
    });

    test('a plain (non-field) parameter', () async {
      await expectNoFindings('a.dart', '''
class A {
  A(int seed) : value = seed;

  final int value;
}
''');
    });
  });

  // --- Exclusions & shape ----------------------------------------------------

  test('generated *.g.dart files are skipped', () async {
    writePubspec();
    writeDart('model.g.dart', '''
class Model {
  const Model(this.value);
  final int value;
}
''');

    expect(await findings(), isEmpty);
  });

  test('user ignore patterns are honored', () async {
    writePubspec();
    writeConfig('ignore:\n  - "lib/legacy/**"\n');
    writeDart('legacy/old.dart', '''
class Old {
  const Old(this.value);
  final int value;
}
''');

    expect(await findings(), isEmpty);
  });

  test('findings carry forward-slash paths and the empty result is well-formed',
      () async {
    writePubspec();
    writeDart('features/home/card.dart', '''
class Card2 {
  const Card2(this.value);
  final int value;
}
''');

    final result = await run();
    expect(result.analyzerName, 'primary-constructors');
    final finding = result.findings.single;
    expect(finding.path, 'lib/features/home/card.dart');
    expect(finding.path, isNot(contains(r'\')));
  });

  test('a missing lib/ yields an empty result', () async {
    writePubspec();
    final result = await run();
    expect(result.analyzerName, 'primary-constructors');
    expect(result.findings, isEmpty);
  });
}
