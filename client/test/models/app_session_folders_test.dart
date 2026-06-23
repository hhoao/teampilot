import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('folders round-trip and derived getters', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/main'),
        WorkspaceFolder(path: '/x'),
      ],
      createdAt: 1,
    );
    expect(s.firstFolderPath, '/main');
    expect(s.extraFolderPaths, ['/x']);
    expect(s.folderPaths, ['/main', '/x']);
    final restored = AppSession.fromJson(s.toJson());
    expect(restored.folders.map((f) => f.path), ['/main', '/x']);
  });

  test('reads folders-only session manifest', () {
    final restored = AppSession.fromJson({
      'sessionId': 's1',
      'workspaceId': 'w1',
      'folders': const [
        {'path': '/main', 'targetId': 'local'},
        {'path': '/x', 'targetId': 'local'},
      ],
      'createdAt': 1,
    });
    expect(restored.firstFolderPath, '/main');
    expect(restored.extraFolderPaths, ['/x']);
  });

  test('toJson writes only folders (no legacy path keys)', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/main')],
      createdAt: 1,
    );
    final json = s.toJson();
    expect((json['folders'] as List).length, 1);
    expect(json.containsKey('primaryPath'), isFalse);
    expect(json.containsKey('additionalPaths'), isFalse);
  });
}
