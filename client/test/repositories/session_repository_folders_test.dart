import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  test('createWorkspace persists local folders and merges by path', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace('/main', additionalPaths: ['/x']);
    expect(ws.folders.map((f) => f.path), ['/main', '/x']);
    expect(
      ws.folders.every((f) => f.targetId == WorkspaceFolder.localTargetId),
      isTrue,
    );

    final merged = await repo.createWorkspace('/main', additionalPaths: ['/y']);
    expect(merged.workspaceId, ws.workspaceId);
    expect(merged.folders.map((f) => f.path), ['/main', '/x', '/y']);
  });

  test('createSession inherits workspace folders; workingDirectory overrides first',
      () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace('/main', additionalPaths: ['/x']);
    final inherited = await repo.createSession(ws.workspaceId);
    expect(inherited.folders.map((f) => f.path), ['/main', '/x']);

    final overridden = await repo.createSession(
      ws.workspaceId,
      workingDirectory: '/override',
    );
    expect(overridden.folders.map((f) => f.path), ['/override', '/x']);
  });

  test('updateWorkspacePaths rewrites folders', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace('/main', additionalPaths: ['/x']);
    await repo.updateWorkspacePaths(ws.workspaceId, '/main2', ['/y', '/z']);
    final reloaded = (await repo.loadWorkspaces()).single;
    expect(reloaded.folders.map((f) => f.path), ['/main2', '/y', '/z']);
  });
}
