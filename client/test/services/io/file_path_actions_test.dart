import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/file_path_actions.dart';

void main() {
  // Fixtures are POSIX absolute paths; pin [p.posix] so Windows CI does not
  // reinterpret `/a/b` via [p.windows] separators.
  final ctx = p.posix;

  group('resolveContainingWorkspaceRoot', () {
    test('picks longest matching folder prefix', () {
      expect(
        resolveContainingWorkspaceRoot(
          '/a/b/c/file.dart',
          ['/a', '/a/b'],
          pathContext: ctx,
        ),
        '/a/b',
      );
    });

    test('returns null when no folder contains path', () {
      expect(
        resolveContainingWorkspaceRoot(
          '/other/x',
          ['/a/b'],
          pathContext: ctx,
        ),
        isNull,
      );
    });
  });

  group('tryRelativeWorkspacePath', () {
    test('returns relative path when inside root', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/ws/src/a.dart',
          workspaceRoot: '/ws',
          pathContext: ctx,
        ),
        'src/a.dart',
      );
    });

    test('returns null when root null', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/ws/a.dart',
          workspaceRoot: null,
          pathContext: ctx,
        ),
        isNull,
      );
    });

    test('returns null when outside root', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/other/a.dart',
          workspaceRoot: '/ws',
          pathContext: ctx,
        ),
        isNull,
      );
    });
  });
}
