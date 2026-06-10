import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:test/test.dart';

void main() {
  final resolver = ImportResolver(
    packageName: 'demo',
    definition: const CleanArchitectureDefinition(),
  );

  List<ResolvedImport> resolve(String source, String importerRelPath) {
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    return resolver.resolve(parsed.unit, importerRelPath, parsed.lineInfo);
  }

  test('classifies an external pub package', () {
    final imports = resolve(
      "import 'package:dio/dio.dart';\nclass X {}\n",
      'lib/features/auth/data/repositories/x.dart',
    );
    expect(imports, hasLength(1));
    expect(imports.single.isInternal, isFalse);
    expect(imports.single.packageName, 'dio');
    expect(imports.single.line, 1);
  });

  test('resolves package:<self>/… to an internal lib/ path', () {
    final imports = resolve(
      "import 'package:demo/features/auth/domain/entities/user.dart';\n",
      'lib/features/auth/presentation/pages/p.dart',
    );
    final import = imports.single;
    expect(import.isInternal, isTrue);
    expect(import.targetRelPath,
        'lib/features/auth/domain/entities/user.dart');
    expect(import.targetLayer!.isEntity, isTrue);
  });

  test('resolves a relative import against the importing file dir', () {
    final imports = resolve(
      "import '../../data/models/user_model.dart';\n",
      'lib/features/auth/domain/entities/user.dart',
    );
    final import = imports.single;
    expect(import.isInternal, isTrue);
    expect(import.targetRelPath, 'lib/features/auth/data/models/user_model.dart');
    expect(import.targetLayer!.isModel, isTrue);
  });

  test('treats dart: imports as external', () {
    final imports = resolve("import 'dart:async';\n", 'lib/main.dart');
    expect(imports.single.isInternal, isFalse);
    expect(imports.single.packageName, 'dart');
  });

  test('records the directive line number', () {
    final imports = resolve(
      "// a comment\n\nimport 'package:dio/dio.dart';\n",
      'lib/x.dart',
    );
    expect(imports.single.line, 3);
  });
}
