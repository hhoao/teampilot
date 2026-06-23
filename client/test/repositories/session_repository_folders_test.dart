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

  test('setWorkspaceTarget stamps all folders with the target id', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace('/main', additionalPaths: ['/x']);
    expect(ws.folders.every((f) => f.targetId == 'local'), isTrue);

    await repo.setWorkspaceTarget(ws.workspaceId, 'ssh:p1');
    final reloaded = (await repo.loadWorkspaces()).single;
    expect(reloaded.folders.map((f) => f.path), ['/main', '/x']);
    expect(reloaded.folders.every((f) => f.targetId == 'ssh:p1'), isTrue);
  });

  test('updateWorkspaceFolders replaces folders wholesale', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace('/main');
    await repo.updateWorkspaceFolders(ws.workspaceId, [
      const WorkspaceFolder(path: '/a', targetId: 'wsl:Ubuntu'),
      const WorkspaceFolder(path: '/b', targetId: 'wsl:Ubuntu'),
    ]);
    final reloaded = (await repo.loadWorkspaces()).single;
    expect(reloaded.folders.map((f) => f.path), ['/a', '/b']);
    expect(reloaded.folders.every((f) => f.targetId == 'wsl:Ubuntu'), isTrue);
  });
}
