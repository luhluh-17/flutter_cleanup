import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('duplicate_widgets_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- Fixture helpers -------------------------------------------------------

  void writePubspec({String name = 'sample'}) {
    File(p.join(tempDir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: $name\n');
  }

  /// Writes a Dart file at [relUnderLib] (relative to `lib/`).
  void writeDart(String relUnderLib, String contents) {
    final file =
        File(p.join(tempDir.path, 'lib', p.joinAll(relUnderLib.split('/'))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  /// Writes a `.flutter_cleanup.yaml` in the project root.
  void writeIgnoreConfig(String contents) {
    File(p.join(tempDir.path, '.flutter_cleanup.yaml'))
        .writeAsStringSync(contents);
  }

  Future<AnalysisResult> run() =>
      const DuplicateWidgetsAnalyzer().analyze(ProjectPaths(tempDir.path));

  /// A StatelessWidget whose `build()` is a `Column` of [children] *distinct*
  /// child widgets (`${prefix}0`, `${prefix}1`, …). Distinct leaf names keep
  /// every size-2 shingle unique, which makes similarity scores predictable.
  ///
  /// The fingerprint length is `children + 1` (the `Column` plus each child), so
  /// pass `children >= 7` to clear [DuplicateWidgetsAnalyzer.minWidgetNodes].
  /// [greeting] and [varName] exercise the "literals/identifiers are ignored"
  /// guarantees: they appear only in a string literal and a local variable name.
  String columnWidget(
    String className, {
    int children = 12,
    String prefix = 'Tile',
    String greeting = 'Hello',
    String varName = 'label',
    bool insertSizedBox = false,
  }) {
    final body = StringBuffer();
    for (var i = 0; i < children; i++) {
      if (insertSizedBox && i == children ~/ 2) {
        body.writeln('          const SizedBox(height: 8),');
      }
      body.writeln('          $prefix$i(),');
    }
    return '''
import 'package:flutter/material.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    final $varName = '$greeting';
    return Column(
      children: [
$body      ],
    );
  }
}
''';
  }

  /// A StatefulWidget + companion `State` whose `build()` mirrors [columnWidget].
  /// The widget name is recovered from `extends State<$className>`.
  String statefulColumnWidget(String className, {int children = 12}) {
    final body = StringBuffer();
    for (var i = 0; i < children; i++) {
      body.writeln('          Tile$i(),');
    }
    return '''
import 'package:flutter/material.dart';

class $className extends StatefulWidget {
  const $className({super.key});

  @override
  State<$className> createState() => _${className}State();
}

class _${className}State extends State<$className> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
$body      ],
    );
  }
}
''';
  }

  // --- Tests -----------------------------------------------------------------

  test('identical widget structure is reported as one pair', () async {
    writePubspec();
    writeDart('a.dart', columnWidget('CardA'));
    writeDart('b.dart', columnWidget('CardB'));

    final result = await run();
    expect(result.analyzerName, 'duplicate-widgets');
    expect(result.findings, hasLength(1));
    expect(result.findings.single.path, 'lib/a.dart');
  });

  test('widgets differing only in string literals are reported', () async {
    writePubspec();
    writeDart('a.dart', columnWidget('CardA', greeting: 'Sign in'));
    writeDart('b.dart',
        columnWidget('CardB', greeting: 'A completely different message'));

    expect((await run()).findings, hasLength(1));
  });

  test('widgets differing only in variable names are reported', () async {
    writePubspec();
    writeDart('a.dart', columnWidget('CardA', varName: 'title'));
    writeDart('b.dart', columnWidget('CardB', varName: 'somethingElse'));

    expect((await run()).findings, hasLength(1));
  });

  test('a single SizedBox inserted between widgets stays above threshold',
      () async {
    writePubspec();
    // 24 distinct children -> 24 unique shingles. One insertion costs one
    // shingle and adds two, so Jaccard = 23/26 ≈ 0.88, still ≥ 0.85.
    writeDart('a.dart', columnWidget('CardA', children: 24));
    writeDart('b.dart',
        columnWidget('CardB', children: 24, insertSizedBox: true));

    expect((await run()).findings, hasLength(1));
  });

  test('structurally unrelated widgets are not reported', () async {
    writePubspec();
    writeDart('a.dart', columnWidget('CardA', prefix: 'Tile'));
    // Same arity, entirely different widget types -> no shared shingles.
    writeDart('b.dart', columnWidget('CardB', prefix: 'Box'));

    expect((await run()).findings, isEmpty);
  });

  test('widgets below the minimum node count do not participate', () async {
    writePubspec();
    // Center + Text = 2 nodes, far below minWidgetNodes (8).
    String tiny(String name) => '''
import 'package:flutter/material.dart';

class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('hi'));
  }
}
''';
    writeDart('a.dart', tiny('TinyA'));
    writeDart('b.dart', tiny('TinyB'));

    expect((await run()).findings, isEmpty);
  });

  test('an ignored file does not participate in comparisons', () async {
    writePubspec();
    writeIgnoreConfig('ignore:\n  - "lib/b.dart"\n');
    writeDart('a.dart', columnWidget('CardA'));
    writeDart('b.dart', columnWidget('CardB'));

    // With b.dart ignored, a.dart has no partner to pair with.
    expect((await run()).findings, isEmpty);
  });

  test('generated *.g.dart duplicate widgets are ignored by default', () async {
    writePubspec();
    writeDart('model.g.dart', columnWidget('CardA'));
    writeDart('other.g.dart', columnWidget('CardB'));

    expect((await run()).findings, isEmpty);
  });

  test('stateful widgets are discovered via their State class', () async {
    writePubspec();
    writeDart('a.dart', statefulColumnWidget('Counter'));
    writeDart('b.dart', statefulColumnWidget('Timer'));

    final result = await run();
    expect(result.findings, hasLength(1));
    // Name is recovered from `State<Foo>`, not the State class name.
    expect(result.findings.single.message, contains('"Counter"'));
    expect(result.findings.single.message, contains('"Timer"'));
  });

  test('stateless widgets are discovered by their class name', () async {
    writePubspec();
    writeDart('a.dart', columnWidget('LoginCard'));
    writeDart('b.dart', columnWidget('RegisterCard'));

    final result = await run();
    expect(result.findings.single.message, contains('"LoginCard"'));
    expect(result.findings.single.message, contains('"RegisterCard"'));
  });

  test('finding paths are forward-slash keyed and correctly shaped', () async {
    writePubspec();
    // 10 children -> fingerprint length 11.
    writeDart('src/widgets/login_card.dart',
        columnWidget('LoginCard', children: 10));
    writeDart('src/widgets/register_card.dart',
        columnWidget('RegisterCard', children: 10));

    final result = await run();
    final finding = result.findings.single;
    // Sorted by path, so login_card (the alphabetically first) is the anchor.
    expect(finding.path, 'lib/src/widgets/login_card.dart');
    expect(finding.path, isNot(contains(r'\')));
    expect(finding.rule, 'duplicate_widget');
    expect(finding.severity, Severity.info);
    expect(
      finding.message,
      'Widget "LoginCard" is highly similar to "RegisterCard" '
      '(100% similarity, 11 nodes).',
    );
  });
}
