import * as assert from 'assert';

import {
  ArchFinding,
  findingMessage,
  groupByFile,
  normalizeSeverity,
  toDiagnosticData,
} from '../diagnosticsMapping';

describe('diagnosticsMapping', () => {
  describe('normalizeSeverity', () => {
    it('maps known severities', () => {
      assert.strictEqual(normalizeSeverity('error'), 'error');
      assert.strictEqual(normalizeSeverity('warning'), 'warning');
      assert.strictEqual(normalizeSeverity('info'), 'info');
    });

    it('falls back to warning for anything unexpected', () => {
      assert.strictEqual(normalizeSeverity('nonsense'), 'warning');
    });
  });

  describe('findingMessage', () => {
    it('appends confidence when present', () => {
      const finding: ArchFinding = {
        rule: 'ARCH209',
        path: 'lib/x.dart',
        severity: 'warning',
        message: 'must implement a contract',
        confidence: 'medium',
      };
      assert.strictEqual(
        findingMessage(finding),
        'must implement a contract (confidence: medium)',
      );
    });

    it('leaves the message untouched when confidence is absent', () => {
      const finding: ArchFinding = {
        rule: 'ARCH101',
        path: 'lib/x.dart',
        severity: 'error',
        message: 'no flutter in domain',
      };
      assert.strictEqual(findingMessage(finding), 'no flutter in domain');
    });
  });

  describe('toDiagnosticData', () => {
    it('maps fields and defaults line/column to 1', () => {
      const data = toDiagnosticData({
        rule: 'ARCH502',
        path: 'lib/features/auth/x.dart',
        severity: 'error',
        message: 'cycle',
      });
      assert.deepStrictEqual(data, {
        path: 'lib/features/auth/x.dart',
        line: 1,
        column: 1,
        code: 'ARCH502',
        message: 'cycle',
        severity: 'error',
      });
    });

    it('preserves an explicit line/column', () => {
      const data = toDiagnosticData({
        rule: 'ARCH110',
        path: 'lib/p.dart',
        severity: 'warning',
        message: 'no repo in page',
        line: 12,
        column: 5,
      });
      assert.strictEqual(data.line, 12);
      assert.strictEqual(data.column, 5);
    });
  });

  describe('groupByFile', () => {
    it('groups multiple findings under the same path', () => {
      const findings: ArchFinding[] = [
        { rule: 'ARCH103', path: 'lib/a.dart', severity: 'warning', message: 'a' },
        { rule: 'ARCH110', path: 'lib/a.dart', severity: 'warning', message: 'b' },
        { rule: 'ARCH101', path: 'lib/b.dart', severity: 'error', message: 'c' },
      ];
      const byFile = groupByFile(findings);
      assert.strictEqual(byFile.size, 2);
      assert.strictEqual(byFile.get('lib/a.dart')?.length, 2);
      assert.strictEqual(byFile.get('lib/b.dart')?.length, 1);
      assert.strictEqual(byFile.get('lib/b.dart')?.[0].code, 'ARCH101');
    });
  });
});
