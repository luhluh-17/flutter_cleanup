import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('duplicate_code_test_');
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
      const DuplicateCodeAnalyzer().analyze(ProjectPaths(tempDir.path));

  Set<String> findingPaths(AnalysisResult result) =>
      result.findings.map((f) => f.path).toSet();

  /// A sizeable class body built from the given statement ids. Each distinct id
  /// yields unique identifiers, so two sources made from different id sets share
  /// only as many tokens as they share ids — well above the analyzer's token
  /// floor.
  String source(Iterable<int> ids) {
    final lines = ids
        .map((n) => '    final result$n = computeValue$n(input$n, factor$n);')
        .join('\n');
    return 'class Sample {\n  void run() {\n$lines\n  }\n}\n';
  }

  // --- Tests -----------------------------------------------------------------

  test('exact duplicates are reported as one pair', () async {
    writePubspec();
    final code = source(List.generate(20, (i) => i));
    writeDart('a.dart', code);
    writeDart('b.dart', code);

    final result = await run();
    expect(result.analyzerName, 'duplicate-code');
    expect(result.findings, hasLength(1));
    expect(findingPaths(result), {'lib/a.dart'});
  });

  test('files differing only in whitespace are reported', () async {
    writePubspec();
    final code = source(List.generate(20, (i) => i));
    writeDart('a.dart', code);
    // Same tokens, mangled whitespace: extra spaces and blank lines.
    writeDart('b.dart', code.replaceAll(' ', '   ').replaceAll(';', ';\n\n'));

    expect((await run()).findings, hasLength(1));
  });

  test('files differing only in comments are reported', () async {
    writePubspec();
    final ids = List.generate(20, (i) => i);
    writeDart('a.dart', source(ids));
    // Same statements, but with line and block comments interleaved.
    final commented = ids
        .map((n) => '    final result$n = computeValue$n(input$n, factor$n);'
            ' // sets result$n\n    /* note for $n */')
        .join('\n');
    writeDart('b.dart', 'class Sample {\n  void run() {\n$commented\n  }\n}\n');

    expect((await run()).findings, hasLength(1));
  });

  test('files differing only in string literals are reported', () async {
    writePubspec();
    String greeter(String greeting) => '''
class Greeter {
  void run() {
    final a = show("$greeting one");
    final b = show("$greeting two");
    final c = show("$greeting three");
    final d = show("$greeting four");
    final e = show("$greeting five");
    final f = show("$greeting six");
  }
}
''';
    writeDart('a.dart', greeter('hello'));
    writeDart('b.dart', greeter('a completely different message'));

    expect((await run()).findings, hasLength(1));
  });

  test('files differing only in numeric literals are reported', () async {
    writePubspec();
    String calc(int seed) => '''
class Calc {
  int run() {
    final a = compute($seed, ${seed + 1});
    final b = compute(${seed + 2}, ${seed + 3});
    final c = compute(${seed + 4}, ${seed + 5});
    final d = compute(${seed + 6}, ${seed + 7});
    final e = compute(${seed + 8}, ${seed + 9});
    return a + b + c + d + e;
  }
}
''';
    writeDart('a.dart', calc(1));
    writeDart('b.dart', calc(100000));

    expect((await run()).findings, hasLength(1));
  });

  test('completely unrelated files are not reported', () async {
    writePubspec();
    writeDart('a.dart', source(List.generate(20, (i) => i)));
    writeDart('b.dart', '''
class Router {
  String resolve(String name) {
    switch (name) {
      case "home":
        return buildHome();
      case "profile":
        return buildProfile();
      case "settings":
        return buildSettings();
      default:
        return buildNotFound();
    }
  }
}
''');

    expect((await run()).findings, isEmpty);
  });

  test('a pair above the threshold is reported', () async {
    writePubspec();
    final ids = List.generate(20, (i) => i);
    writeDart('a.dart', source(ids));
    // Change a single statement out of twenty -> still well above 80%.
    writeDart('b.dart', source([...ids.where((i) => i != 10), 999]));

    expect((await run()).findings, hasLength(1));
  });

  test('a pair below the threshold is not reported', () async {
    writePubspec();
    writeDart('a.dart', source(List.generate(20, (i) => i)));
    // Share only 8 of 20 statements; the other 12 are unique -> ~25%.
    writeDart(
      'b.dart',
      source([...List.generate(8, (i) => i), ...List.generate(12, (i) => 100 + i)]),
    );

    expect((await run()).findings, isEmpty);
  });

  test('finding paths are forward-slash keyed and correctly shaped', () async {
    writePubspec();
    final code = source(List.generate(20, (i) => i));
    writeDart('src/widgets/card.dart', code);
    writeDart('src/widgets/card_copy.dart', code);

    final result = await run();
    final finding = result.findings.single;
    expect(finding.path, 'lib/src/widgets/card.dart');
    expect(finding.path, isNot(contains(r'\')));
    expect(finding.rule, 'duplicate_code');
    expect(finding.severity, Severity.info);
    expect(
      finding.message,
      'Highly similar to lib/src/widgets/card_copy.dart (100% similarity).',
    );
  });

  test('empty and below-floor files yield no findings', () async {
    writePubspec();
    writeDart('empty_a.dart', '');
    writeDart('empty_b.dart', '   \n  // only a comment\n');
    writeDart('tiny_a.dart', 'class A {}');
    writeDart('tiny_b.dart', 'class B {}');

    expect((await run()).findings, isEmpty);
  });

  test('an ignored file does not participate in comparisons', () async {
    writePubspec();
    writeIgnoreConfig('ignore:\n  - "lib/b.dart"\n');
    final code = source(List.generate(20, (i) => i));
    writeDart('a.dart', code);
    writeDart('b.dart', code);

    // With b.dart ignored, there is no second candidate to pair with a.dart.
    expect((await run()).findings, isEmpty);
  });

  test('generated *.g.dart duplicates are ignored by default', () async {
    writePubspec();
    final code = source(List.generate(20, (i) => i));
    writeDart('model.g.dart', code);
    writeDart('other.g.dart', code);

    expect((await run()).findings, isEmpty);
  });
}
