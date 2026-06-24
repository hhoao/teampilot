import 'dart:io';

import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createSession with workingDirectory overrides primaryPath', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_wd_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/repo/main')]);
    final session = await repo.createSession(
      ws.workspaceId,
      personalIdentityId: 'p',
      workingDirectory: '/repo/main/../wt/feat',
    );
    // normalizeWorkspacePath collapses '..' → '/repo/wt/feat'
    expect(session.firstFolderPath, '/repo/wt/feat');
  });

  test('createSession without workingDirectory keeps workspace.firstFolderPath', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_wd_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/repo/main')]);
    final session = await repo.createSession(ws.workspaceId, personalIdentityId: 'p');
    expect(session.firstFolderPath, '/repo/main');
  });
}
