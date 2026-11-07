import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('same root string on another plane does not leak the workspace index',
      () async {
    final fsA = InMemoryFilesystem();
    final fsB = InMemoryFilesystem();
    // Two remote hosts with the same user name resolve the same root string.
    const root = '/home/ubuntu/.teampilot';

    final repoA = SessionRepository(
      rootDir: root,
      storage: fakeHomeStorage(filesystem: fsA, appDataRoot: root),
    );
    final repoB = SessionRepository(
      rootDir: root,
      storage: fakeHomeStorage(filesystem: fsB, appDataRoot: root),
    );

    final workspace = await repoA.createWorkspace([
      const WorkspaceFolder(path: '/srv/app-a'),
    ]);
    final indexA = await repoA.loadWorkspacesIndex();
    expect(indexA.map((w) => w.workspaceId), [workspace.workspaceId]);

    final indexB = await repoB.loadWorkspacesIndex();
    expect(indexB, isEmpty);
  });
}
