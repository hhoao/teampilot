import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('json round-trip carries no teamId', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: const [WorkspaceFolder(path: '/tmp/repo')],
      display: 'Repo',
      createdAt: 1,
      updatedAt: 2,
    );
    final json = workspace.toJson();
    expect(json.containsKey('teamId'), isFalse);
    final restored = Workspace.fromJson(json);
    expect(restored.workspaceId, 'p1');
    expect(restored.firstFolderPath, '/tmp/repo');
    expect(restored.display, 'Repo');
  });

  test('folders round-trip and expose derived path getters', () {
    final ws = Workspace(
      workspaceId: 'p1',
      folders: const [
        WorkspaceFolder(path: '/main'),
        WorkspaceFolder(path: '/extra'),
      ],
      createdAt: 1,
    );
    expect(ws.firstFolderPath, '/main');
    expect(ws.extraFolderPaths, ['/extra']);
    expect(ws.folderPaths, ['/main', '/extra']);
    final restored = Workspace.fromJson(ws.toJson());
    expect(restored.folders.map((f) => f.path), ['/main', '/extra']);
    expect(restored.folders.every((f) => f.targetId == 'local'), isTrue);
  });

  test('reads legacy primaryPath + additionalPaths manifest', () {
    final restored = Workspace.fromJson({
      'workspaceId': 'p1',
      'primaryPath': '/main',
      'additionalPaths': ['/extra'],
      'createdAt': 1,
    });
    expect(restored.firstFolderPath, '/main');
    expect(restored.extraFolderPaths, ['/extra']);
  });

  test('toJson dual-writes legacy fields alongside folders', () {
    final ws = Workspace(
      workspaceId: 'p1',
      folders: const [
        WorkspaceFolder(path: '/main'),
        WorkspaceFolder(path: '/x'),
      ],
      createdAt: 1,
    );
    final json = ws.toJson();
    expect((json['folders'] as List).length, 2);
    expect(json['primaryPath'], '/main');
    expect(json['additionalPaths'], ['/x']);
  });

  test('legacy teamId key in json is ignored on read', () {
    final restored = Workspace.fromJson({
      'workspaceId': 'p1',
      'primaryPath': '/tmp/repo',
      'teamId': 'old-team',
      'createdAt': 1,
    });
    expect(restored.workspaceId, 'p1');
    // No teamId surface exists; the field is simply dropped.
  });

  test('defaultProfileId round-trips and defaults empty', () {
    final p = Workspace(
      workspaceId: 'p1',
      folders: const [WorkspaceFolder(path: '/tmp/p1')],
      createdAt: 1,
      defaultProfileId: 'coding',
    );
    final restored = Workspace.fromJson(p.toJson());
    expect(restored.defaultProfileId, 'coding');
    expect(
      Workspace.fromJson({'workspaceId': 'x', 'primaryPath': '/x'})
          .defaultProfileId,
      '',
    );
  });
}
