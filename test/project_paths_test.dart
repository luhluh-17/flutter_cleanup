import 'package:flutter_cleanup/flutter_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Explicit contexts make these assertions deterministic regardless of the
  // host OS: with the default `p` context, `C:\...` would only be recognized as
  // absolute on Windows and `/home/...` only on POSIX.
  final windows = p.Context(style: p.Style.windows, current: r'C:\cwd');
  final posix = p.Context(style: p.Style.posix, current: '/cwd');

  group('relative paths resolve against the current directory', () {
    test('"." resolves to the current directory', () {
      expect(ProjectPaths('.', context: windows).root, r'C:\cwd');
    });

    test('a subdirectory resolves under the current directory (Windows)', () {
      expect(ProjectPaths('test_project', context: windows).root,
          r'C:\cwd\test_project');
    });

    test('a subdirectory resolves under the current directory (POSIX)', () {
      expect(ProjectPaths('test_project', context: posix).root,
          '/cwd/test_project');
    });
  });

  group('absolute paths are used directly', () {
    test('an absolute Windows path stays absolute', () {
      final paths =
          ProjectPaths(r'C:\Users\Test\MyProject', context: windows);

      expect(paths.root, r'C:\Users\Test\MyProject');
      // Regression: must NOT be joined onto the cwd.
      expect(paths.root, isNot(contains(r'C:\cwd')));
    });

    test('an absolute POSIX path stays absolute', () {
      expect(ProjectPaths('/home/user/project', context: posix).root,
          '/home/user/project');
    });
  });

  group('drive-relative (mangled) Windows paths are rejected', () {
    test('a drive letter with no separator throws on Windows style', () {
      // What a bash shell leaves after eating the backslashes of
      // C:\Users\Test\MyProject.
      expect(
        () => ProjectPaths('C:UsersTestMyProject', context: windows),
        throwsA(isA<InvalidProjectPathException>()),
      );
    });

    test('the same string is a normal relative path under POSIX style', () {
      // On POSIX, "C:UsersTestMyProject" is a legitimate relative directory
      // name, so the guard must not misfire.
      expect(ProjectPaths('C:UsersTestMyProject', context: posix).root,
          '/cwd/C:UsersTestMyProject');
    });
  });
}
