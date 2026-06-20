import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  /// Every ARCH code a rule can currently emit. When a new code is added to a
  /// rule, add it here too — the completeness test below then forces a matching
  /// recommendation entry.
  const allCodes = [
    'ARCH101', 'ARCH102', 'ARCH103', 'ARCH104', 'ARCH105', // layer imports
    'ARCH106', 'ARCH107', 'ARCH108', 'ARCH109', 'ARCH110', // layer purity
    'ARCH202', // completeness (data layer without a domain layer)
    'ARCH204', 'ARCH205', 'ARCH206', 'ARCH207', 'ARCH208', 'ARCH209', // placement
    'ARCH210', 'ARCH211', 'ARCH212', // vocabulary
    'ARCH301', // riverpod
    'ARCH401', 'ARCH402', 'ARCH403', // routing
    'ARCH501', 'ARCH502', 'ARCH503', // feature boundaries
  ];

  test('every emittable ARCH code has a recommendation', () {
    for (final code in allCodes) {
      expect(recommendationFor(code), isNotNull, reason: code);
      expect(recommendationFor(code), isNotEmpty, reason: code);
    }
  });

  test('unknown codes degrade to null instead of throwing', () {
    expect(recommendationFor('ARCH999'), isNull);
  });

  group('analyzer findings carry recommendations', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_cleanup_reco_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('in both the finding and its JSON projection', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      final file = File(p.join(
          tempDir.path, 'lib', 'features', 'a', 'state', 'providers.dart'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('class A {}\n');

      final result =
          await ArchitectureAnalyzer().analyze(ProjectPaths(tempDir.path));
      final finding = result.findings.firstWhere((f) => f.rule == 'ARCH210');

      expect(finding.recommendation, recommendationFor('ARCH210'));
      expect(finding.toJson()['recommendation'], recommendationFor('ARCH210'));
    });
  });
}
