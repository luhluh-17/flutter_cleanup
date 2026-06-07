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

  group('JSON serialization', () {
    test('Finding.toJson emits rule/path/severity-name/message', () {
      const finding = Finding(
        rule: 'duplicate_widget',
        path: 'lib/widgets/login_card.dart',
        severity: Severity.info,
        message: 'Widget "LoginCard" is highly similar to "RegisterCard".',
      );

      expect(finding.toJson(), {
        'rule': 'duplicate_widget',
        'path': 'lib/widgets/login_card.dart',
        'severity': 'info',
        'message': 'Widget "LoginCard" is highly similar to "RegisterCard".',
      });
    });

    test('AnalysisResult.toJson uses the analyzer key and nests findings', () {
      const finding = Finding(
        rule: 'unused_asset',
        path: 'assets/logo.png',
        severity: Severity.warning,
        message: 'Asset is never referenced.',
      );
      const result =
          AnalysisResult(analyzerName: 'unused-assets', findings: [finding]);

      final json = result.toJson();
      expect(json['analyzer'], 'unused-assets');
      expect(json['findings'], hasLength(1));
      expect((json['findings'] as List).single, finding.toJson());
    });

    test('AnalysisResult.toJson serializes empty results as an empty list', () {
      const result = AnalysisResult.empty('duplicate-code');

      expect(result.toJson(), {
        'analyzer': 'duplicate-code',
        'findings': <Object>[],
      });
    });
  });

  group('ReportPrinter output formats', () {
    final report = ValidationReport([const ValidationResult.ok('lib/ found')]);

    test('text format renders without error', () {
      final printer = ReportPrinter(Logger(useColor: false));
      expect(() => printer.validationReport(report), returnsNormally);
    });

    test('json format renders without throwing', () {
      final printer =
          ReportPrinter(Logger(useColor: false), format: OutputFormat.json);
      expect(() => printer.validationReport(report), returnsNormally);
      expect(
        () => printer.findings(
          const AnalysisResult.empty('unused-assets'),
          title: 'Unused assets',
          itemNoun: 'unused asset',
        ),
        returnsNormally,
      );
    });
  });
}
