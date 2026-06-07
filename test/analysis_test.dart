import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:test/test.dart';

void main() {
  group('Finding / AnalysisResult', () {
    test('AnalysisResult.empty has no findings', () {
      const result = AnalysisResult.empty('unused-assets');
      expect(result.analyzerName, 'unused-assets');
      expect(result.hasFindings, isFalse);
    });

    test('AnalysisResult exposes its findings', () {
      const finding = Finding(
        rule: 'unused_asset',
        path: 'assets/logo.png',
        severity: Severity.warning,
        message: 'Asset is never referenced.',
      );
      const result =
          AnalysisResult(analyzerName: 'unused-assets', findings: [finding]);

      expect(result.hasFindings, isTrue);
      expect(result.findings.single.severity, Severity.warning);
    });
  });

  group('ReportPrinter output formats', () {
    final report = ValidationReport([const ValidationResult.ok('lib/ found')]);

    test('text format renders without error', () {
      final printer = ReportPrinter(Logger(useColor: false));
      expect(() => printer.validationReport(report), returnsNormally);
    });

    test('json format is reserved but not yet implemented', () {
      final printer =
          ReportPrinter(Logger(useColor: false), format: OutputFormat.json);
      expect(
        () => printer.validationReport(report),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
