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
}
