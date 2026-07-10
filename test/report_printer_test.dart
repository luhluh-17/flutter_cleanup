import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('report_printer_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Renders [result] in text mode and returns the raw output.
  Future<String> renderText(AnalysisResult result) async {
    final outFile = File(p.join(tempDir.path, 'out.txt'));
    final sink = outFile.openWrite();
    final logger = Logger(useColor: false, out: sink, err: sink);
    ReportPrinter(logger).findings(result, title: 'T', itemNoun: 'item');
    await sink.flush();
    await sink.close();
    return outFile.readAsStringSync();
  }

  Finding finding({int? line, int? column}) => Finding(
        rule: 'ARCH501',
        path: 'lib/features/a/presentation/widgets/w.dart',
        severity: Severity.warning,
        message: 'Cross-feature import.',
        line: line,
        column: column,
      );

  test('text findings include path:line when the line is known', () async {
    final raw = await renderText(AnalysisResult(
      analyzerName: 'architecture',
      findings: [finding(line: 12)],
    ));

    expect(raw,
        contains('lib/features/a/presentation/widgets/w.dart:12 — '));
  });

  test('text findings include path:line:column when both are known', () async {
    final raw = await renderText(AnalysisResult(
      analyzerName: 'architecture',
      findings: [finding(line: 12, column: 3)],
    ));

    expect(raw,
        contains('lib/features/a/presentation/widgets/w.dart:12:3 — '));
  });

  test('text findings print the recommendation under the violation', () async {
    final raw = await renderText(AnalysisResult(
      analyzerName: 'architecture',
      findings: const [
        Finding(
          rule: 'ARCH501',
          path: 'lib/features/a/presentation/widgets/w.dart',
          severity: Severity.warning,
          message: 'Cross-feature import.',
          line: 12,
          recommendation: 'Extract the shared code into core/.',
        ),
      ],
    ));

    expect(raw, contains('    ↳ Extract the shared code into core/.'));
  });

  test('identical findings are grouped with one message and recommendation',
      () async {
    Finding cross(String path, int line) => Finding(
          rule: 'ARCH501',
          path: path,
          severity: Severity.warning,
          message: 'Cross-feature import: "a" must not import "b".',
          line: line,
          recommendation: 'Extract the shared code into core/.',
        );

    final raw = await renderText(AnalysisResult(
      analyzerName: 'architecture',
      findings: [
        cross('lib/features/a/presentation/widgets/z.dart', 9),
        cross('lib/features/a/presentation/widgets/w.dart', 5),
        cross('lib/features/a/presentation/widgets/w.dart', 6),
      ],
    ));

    // One headline with the count, locations sorted by path then line,
    // and the recommendation printed exactly once.
    expect(
        raw,
        contains('Cross-feature import: "a" must not import "b". '
            '(3 occurrences)\n'
            '    lib/features/a/presentation/widgets/w.dart:5\n'
            '    lib/features/a/presentation/widgets/w.dart:6\n'
            '    lib/features/a/presentation/widgets/z.dart:9\n'
            '    ↳ Extract the shared code into core/.'));
    expect('Cross-feature import'.allMatches(raw), hasLength(1));
    expect(raw, contains('3 items found (1 distinct issue).'));
  });

  test('different messages stay as separate classic lines', () async {
    final raw = await renderText(AnalysisResult(
      analyzerName: 'architecture',
      findings: const [
        Finding(
          rule: 'ARCH105',
          path: 'lib/features/a/presentation/widgets/w.dart',
          severity: Severity.warning,
          message: 'Presentation may only access use cases (imported domain).',
          line: 4,
        ),
        Finding(
          rule: 'ARCH105',
          path: 'lib/features/b/presentation/widgets/x.dart',
          severity: Severity.warning,
          message: 'Presentation may only access use cases (imported data).',
          line: 7,
        ),
      ],
    ));

    expect(
        raw,
        contains('lib/features/a/presentation/widgets/w.dart:4 — '
            'Presentation may only access use cases (imported domain).'));
    expect(
        raw,
        contains('lib/features/b/presentation/widgets/x.dart:7 — '
            'Presentation may only access use cases (imported data).'));
    expect(raw, contains('2 items found.'));
  });

  test('text findings omit the location suffix when the line is unknown',
      () async {
    final raw = await renderText(AnalysisResult(
      analyzerName: 'unused-assets',
      findings: [finding()],
    ));

    expect(raw,
        contains('lib/features/a/presentation/widgets/w.dart — '));
    expect(raw, isNot(contains('w.dart:')));
  });

  group('maintainability thresholds legend', () {
    Future<String> renderLegend(
      MaintainabilityConfig config, {
      OutputFormat format = OutputFormat.text,
    }) async {
      final outFile = File(p.join(tempDir.path, 'legend.txt'));
      final sink = outFile.openWrite();
      final logger = Logger(useColor: false, out: sink, err: sink);
      ReportPrinter(logger, format: format).maintainabilityThresholds(config);
      await sink.flush();
      await sink.close();
      return outFile.readAsStringSync();
    }

    test('text mode prints the accepted-standards table', () async {
      final raw = await renderLegend(const MaintainabilityConfig());

      expect(raw, contains('Accepted standards (limit)'));
      expect(raw, contains('Widget file'));
      expect(raw, contains('≤ 250 lines'));
      expect(raw, contains('Controller'));
      expect(raw, contains('≤ 300 lines'));
      expect(raw, contains('Widget nesting'));
      expect(raw, contains('≤ 5 levels'));
      expect(raw, contains('Public classes'));
      expect(raw, contains('≤ 1 per file'));
      expect(raw, contains('Folder'));
      expect(raw, contains('≤ 15 files'));
    });

    test('reflects custom configured limits', () async {
      final raw = await renderLegend(const MaintainabilityConfig(
        methodLines: 20,
      ));

      expect(raw, contains('≤ 20 lines'));
    });

    test('json mode emits nothing (legend is text-only chrome)', () async {
      final raw = await renderLegend(
        const MaintainabilityConfig(),
        format: OutputFormat.json,
      );

      expect(raw, isEmpty);
    });
  });

  group('grouped maintainability findings', () {
    Future<String> renderGrouped(
      AnalysisResult result, {
      MaintainabilityConfig config = const MaintainabilityConfig(),
      OutputFormat format = OutputFormat.text,
    }) async {
      final outFile = File(p.join(tempDir.path, 'grouped.txt'));
      final sink = outFile.openWrite();
      final logger = Logger(useColor: false, out: sink, err: sink);
      ReportPrinter(logger, format: format)
          .maintainabilityFindings(result, config);
      await sink.flush();
      await sink.close();
      return outFile.readAsStringSync();
    }

    Finding mFinding(String rule, String message, {String path = 'lib/a.dart'}) =>
        Finding(
          rule: rule,
          path: path,
          severity: Severity.warning,
          message: message,
          recommendation: 'Fix it.',
        );

    test('groups findings under per-metric sub-headings in canonical order',
        () async {
      final raw = await renderGrouped(AnalysisResult(
        analyzerName: 'maintainability',
        findings: [
          mFinding('method_length', 'Method foo() contains 40 lines (limit: 30).'),
          mFinding('folder_file_count', 'Folder contains 20 Dart files (limit: 15).',
              path: 'lib/features'),
          mFinding('widget_file_length',
              'Widget file contains 312 lines (limit: 250).'),
        ],
      ));

      expect(raw, contains('Folder (≤ 15 files)'));
      expect(raw, contains('Widget file (≤ 250 lines)'));
      expect(raw, contains('Method (≤ 30 lines)'));
      // Canonical order: Folder before Widget file before Method.
      expect(raw.indexOf('Folder (≤ 15 files)'),
          lessThan(raw.indexOf('Widget file (≤ 250 lines)')));
      expect(raw.indexOf('Widget file (≤ 250 lines)'),
          lessThan(raw.indexOf('Method (≤ 30 lines)')));
      expect(raw, contains('3 maintainability issues found.'));
    });

    test('empty result reports success', () async {
      final raw = await renderGrouped(
        AnalysisResult.empty('maintainability'),
      );
      expect(raw, contains('No maintainability issues found.'));
    });

    test('json mode emits a single analyzer document', () async {
      final raw = await renderGrouped(
        AnalysisResult(analyzerName: 'maintainability', findings: [
          mFinding('method_length', 'Method foo() contains 40 lines (limit: 30).'),
        ]),
        format: OutputFormat.json,
      );
      expect(raw, contains('"analyzer": "maintainability"'));
      expect(raw, contains('"rule": "method_length"'));
    });
  });
}
