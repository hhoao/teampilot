import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  test('createWorkspace persists local folders and merges by path', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
      const WorkspaceFolder(path: '/x'),
    ]);
    expect(ws.folders.map((f) => f.path), ['/main', '/x']);
    expect(
      ws.folders.every((f) => f.targetId == WorkspaceFolder.localTargetId),
      isTrue,
    );

    final merged = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
      const WorkspaceFolder(path: '/y'),
    ]);
    expect(merged.workspaceId, ws.workspaceId);
    expect(merged.folders.map((f) => f.path), ['/main', '/x', '/y']);
  });

  test('createSession inherits workspace folders; workingDirectory overrides first',
      () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
      const WorkspaceFolder(path: '/x'),
    ]);
    final inherited = await repo.createSession(ws.workspaceId);
    expect(inherited.folders.map((f) => f.path), ['/main', '/x']);

    final overridden = await repo.createSession(
      ws.workspaceId,
      workingDirectory: '/override',
    );
    expect(overridden.folders.map((f) => f.path), ['/override', '/x']);
  });

  test('updateWorkspaceFolders rewrites folders', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
      const WorkspaceFolder(path: '/x'),
    ]);
    await repo.updateWorkspaceFolders(ws.workspaceId, [
      const WorkspaceFolder(path: '/main2'),
      const WorkspaceFolder(path: '/y'),
      const WorkspaceFolder(path: '/z'),
    ]);
    final reloaded = (await repo.loadWorkspaces()).single;
    expect(reloaded.folders.map((f) => f.path), ['/main2', '/y', '/z']);
  });

  test('updateWorkspaceFolders can stamp all folders with one target', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
      const WorkspaceFolder(path: '/x'),
    ]);
    expect(ws.folders.every((f) => f.targetId == 'local'), isTrue);

    await repo.updateWorkspaceFolders(ws.workspaceId, [
      for (final f in ws.folders) f.copyWith(targetId: 'ssh:p1'),
    ]);
    final reloaded = (await repo.loadWorkspaces()).single;
    expect(reloaded.folders.map((f) => f.path), ['/main', '/x']);
    expect(reloaded.folders.every((f) => f.targetId == 'ssh:p1'), isTrue);
  });

  test('setMemberTarget writes + clears per-member target', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
      const WorkspaceFolder(path: '/x'),
    ]);
    final s = await repo.createSession(ws.workspaceId);

    await repo.setMemberTarget(s.sessionId, 'm1', 'local');
    var reloaded = (await repo.loadSessions()).single;
    expect(reloaded.memberTargets['m1'], 'local');

    await repo.setMemberTarget(s.sessionId, 'm1', '');
    reloaded = (await repo.loadSessions()).single;
    expect(reloaded.memberTargets.containsKey('m1'), isFalse);
  });

  test('updateWorkspaceFolders replaces folders wholesale', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/main'),
    ]);
    await repo.updateWorkspaceFolders(ws.workspaceId, [
      const WorkspaceFolder(path: '/a', targetId: 'wsl:Ubuntu'),
      const WorkspaceFolder(path: '/b', targetId: 'wsl:Ubuntu'),
    ]);
    final reloaded = (await repo.loadWorkspaces()).single;
    expect(reloaded.folders.map((f) => f.path), ['/a', '/b']);
    expect(reloaded.folders.every((f) => f.targetId == 'wsl:Ubuntu'), isTrue);
  });

  test('mixed topology via per-folder targets', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);
    expect(ws.folders.first.targetId, WorkspaceFolder.localTargetId);
    expect(ws.folders.last.targetId, 'ssh:p1');
  });

  test('createSession seeds remembered mixed-workspace member targets', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);
    await repo.updateWorkspaceMemberTargets(
      ws.workspaceId,
      'team-a',
      targets: const {
        'lead': 'local',
        'dev': 'ssh:p1',
      },
    );

    final session = await repo.createSession(
      ws.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'lead', name: 'Lead'),
        TeamMemberConfig(id: 'dev', name: 'Dev'),
      ],
    );
    expect(session.memberTargets['lead'], 'local');
    expect(session.memberTargets['dev'], 'ssh:p1');
  });

  test('replaceMemberTargets writes targets atomically', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);
    final session = await repo.createSession(
      ws.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'lead', name: 'Lead'),
      ],
    );
    await repo.replaceMemberTargets(
      session.sessionId,
      targets: const {
        'lead': 'ssh:p1',
      },
      instanceIdsToClear: const {'lead'},
    );
    final reloaded = (await repo.loadSessions()).single;
    expect(reloaded.memberTargets['lead'], 'ssh:p1');
  });
}
