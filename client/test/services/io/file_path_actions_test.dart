import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/file_path_actions.dart';

void main() {
  group('resolveContainingWorkspaceRoot', () {
    test('picks longest matching folder prefix', () {
      expect(
        resolveContainingWorkspaceRoot(
          '/a/b/c/file.dart',
          ['/a', '/a/b'],
        ),
        '/a/b',
      );
    });

    test('returns null when no folder contains path', () {
      expect(
        resolveContainingWorkspaceRoot('/other/x', ['/a/b']),
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
        ),
        'src/a.dart',
      );
    });

    test('returns null when root null', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/ws/a.dart',
          workspaceRoot: null,
        ),
        isNull,
      );
    });

    test('returns null when outside root', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/other/a.dart',
          workspaceRoot: '/ws',
        ),
        isNull,
      );
    });
  });
}
