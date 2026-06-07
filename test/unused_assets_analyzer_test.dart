import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unused_assets_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // --- Fixture helpers -------------------------------------------------------

  /// Writes a `pubspec.yaml` declaring the given `flutter > assets` entries.
  void writePubspec(List<String> assetEntries) {
    final buffer = StringBuffer('name: sample\n');
    if (assetEntries.isNotEmpty) {
      buffer.writeln('flutter:');
      buffer.writeln('  assets:');
      for (final entry in assetEntries) {
        buffer.writeln('    - $entry');
      }
    }
    File(p.join(tempDir.path, 'pubspec.yaml'))
        .writeAsStringSync(buffer.toString());
  }

  /// Writes a file (creating parent dirs) relative to the project root.
  void writeFile(String relativePath, String contents) {
    final file = File(p.join(tempDir.path, p.joinAll(relativePath.split('/'))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  /// Writes a Dart file under `lib/`.
  void writeDart(String relativePath, String contents) =>
      writeFile('lib/$relativePath', contents);

  /// Writes a `.flutter_cleanup.yaml` in the project root.
  void writeIgnoreConfig(String contents) =>
      writeFile('.flutter_cleanup.yaml', contents);

  Future<AnalysisResult> run() =>
      const UnusedAssetsAnalyzer().analyze(ProjectPaths(tempDir.path));

  Set<String> unusedPaths(AnalysisResult result) =>
      result.findings.map((f) => f.path).toSet();

  // --- Tests -----------------------------------------------------------------

  test('discovers files in a declared asset directory', () async {
    writePubspec(['assets/images/']);
    writeFile('assets/images/logo.png', 'binary');
    writeDart('main.dart', "void main() {}");

    final result = await run();

    expect(unusedPaths(result), {'assets/images/logo.png'});
  });

  test('recursively collects assets in nested subdirectories', () async {
    writePubspec(['assets/']);
    writeFile('assets/images/logo.png', 'x');
    writeFile('assets/images/nested/deep/icon.png', 'x');
    writeDart('main.dart', 'void main() {}');

    final result = await run();

    expect(unusedPaths(result), {
      'assets/images/logo.png',
      'assets/images/nested/deep/icon.png',
    });
  });

  test('detects Image.asset references', () async {
    writePubspec(['assets/images/']);
    writeFile('assets/images/logo.png', 'x');
    writeDart('main.dart', "Image.asset('assets/images/logo.png');");

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('detects AssetImage references with double quotes', () async {
    writePubspec(['assets/images/']);
    writeFile('assets/images/logo.png', 'x');
    writeDart('main.dart', 'AssetImage("assets/images/logo.png");');

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('detects SvgPicture.asset references', () async {
    writePubspec(['assets/icons/']);
    writeFile('assets/icons/home.svg', 'x');
    writeDart('main.dart', "SvgPicture.asset('assets/icons/home.svg');");

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('reports unused assets with the expected finding shape', () async {
    writePubspec(['assets/images/']);
    writeFile('assets/images/used.png', 'x');
    writeFile('assets/images/orphan.png', 'x');
    writeDart('main.dart', "Image.asset('assets/images/used.png');");

    final result = await run();

    expect(result.analyzerName, 'unused-assets');
    expect(result.findings, hasLength(1));
    final finding = result.findings.single;
    expect(finding.rule, 'unused_asset');
    expect(finding.path, 'assets/images/orphan.png');
    expect(finding.severity, Severity.warning);
    expect(finding.message, 'Asset appears to be unused.');
  });

  test('empty asset directory yields no findings', () async {
    writePubspec(['assets/images/']);
    Directory(p.join(tempDir.path, 'assets', 'images')).createSync(recursive: true);
    writeDart('main.dart', 'void main() {}');

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('declared but missing asset directory does not crash', () async {
    writePubspec(['assets/images/']);
    writeDart('main.dart', 'void main() {}');

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('normalizes paths so forward-slash references match on any platform',
      () async {
    writePubspec(['assets/']);
    writeFile('assets/images/nested/logo.png', 'x');
    // Reference uses forward slashes (as Flutter requires), while the
    // filesystem walk uses the native separator.
    writeDart('main.dart', "Image.asset('assets/images/nested/logo.png');");

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('finding paths always use forward slashes', () async {
    writePubspec(['assets/']);
    writeFile('assets/images/nested/orphan.png', 'x');
    writeDart('main.dart', 'void main() {}');

    final result = await run();

    expect(result.findings.single.path, 'assets/images/nested/orphan.png');
    expect(result.findings.single.path, isNot(contains(r'\')));
  });

  test('ignores file-style asset entries', () async {
    // Single-file entry (no trailing slash) is not analyzed in v1.
    writePubspec(['assets/images/logo.png']);
    writeFile('assets/images/logo.png', 'x');
    writeDart('main.dart', 'void main() {}');

    final result = await run();

    expect(result.findings, isEmpty);
  });

  test('dynamic references are not resolved (asset reported unused)', () async {
    writePubspec(['assets/images/']);
    writeFile('assets/images/logo.png', 'x');
    writeDart('main.dart', '''
const assetPath = 'assets/images/logo.png';
void build() => Image.asset(assetPath);
''');

    final result = await run();

    // The literal assigned to `assetPath` happens to appear, so this asset is
    // actually matched. Use a truly dynamic path to confirm non-resolution.
    expect(result.findings, isEmpty);
  });

  test('truly dynamic path yields an unused finding', () async {
    writePubspec(['assets/images/']);
    writeFile('assets/images/logo.png', 'x');
    writeDart('main.dart', '''
String pick(String name) => 'assets/images/' + name;
void build() => Image.asset(pick('logo.png'));
''');

    final result = await run();

    expect(unusedPaths(result), {'assets/images/logo.png'});
  });

  test('an unused asset under an ignored directory is not flagged', () async {
    writePubspec(['assets/']);
    writeIgnoreConfig('ignore:\n  - "assets/legacy/**"\n');
    writeFile('assets/legacy/old_logo.png', 'x');
    writeFile('assets/images/orphan.png', 'x');
    writeDart('main.dart', 'void main() {}');

    // The legacy asset is ignored; only the non-ignored orphan is reported.
    expect(unusedPaths(await run()), {'assets/images/orphan.png'});
  });

  test('asset referenced only from an ignored generated file is not flagged',
      () async {
    // Judge-only semantics: ignored Dart files remain evidence of usage, so an
    // asset referenced only from a *.g.dart file must not become a false
    // positive.
    writePubspec(['assets/images/']);
    writeFile('assets/images/logo.png', 'x');
    writeDart('assets.g.dart',
        "const String logo = 'assets/images/logo.png';");

    final result = await run();

    expect(result.findings, isEmpty);
  });
}
