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

  test(
    'createSession inherits workspace folders; workingDirectory overrides first',
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
      expect(overridden.folders.map((f) => f.path), ['/override', '/main', '/x']);
    },
  );

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

  test(
    'updateWorkspaceFolders can stamp all folders with one target',
    () async {
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
    },
  );

  test('createSession allows personal launch on mixed workspace', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);

    final session = await repo.createSession(
      ws.workspaceId,
      workingDirectory: '/remote',
    );
    expect(session.folders.first.path, '/remote');
    expect(session.folders.last.path, '/local');
  });

  test(
    'createSession rejects mixed workspace when placement not initialized',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);

      expect(
        () => repo.createSession(
          ws.workspaceId,
          sessionTeam: 'team-a',
          rosterMembers: const [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'mixed_workspace_member_placement_uninitialized',
          ),
        ),
      );
    },
  );

  test(
    'updateWorkspaceFolders clears init flags when host set changes to mixed',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'local'},
      );
      expect(
        (await repo.loadWorkspaces())
            .single
            .memberPlacementInitializedByTeam['team-a'],
        isTrue,
      );

      await repo.updateWorkspaceFolders(ws.workspaceId, [
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);

      final reloaded = (await repo.loadWorkspaces()).single;
      expect(reloaded.memberPlacementInitializedByTeam['team-a'], isNot(true));
      expect(reloaded.memberPlacementInitializedByTeam, isEmpty);
    },
  );

  test('createSession snapshots workspace team targets immutably', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);
    await repo.updateWorkspaceMemberPlacement(
      ws.workspaceId,
      'team-a',
      targets: const {'team-lead': 'local'},
    );
    final session = await repo.createSession(
      ws.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
    );
    expect(session.memberTargets['team-lead'], 'local');

    await repo.updateWorkspaceMemberTargets(
      ws.workspaceId,
      'team-a',
      targets: const {'team-lead': 'ssh:p1'},
    );
    final reloaded = (await repo.loadSessions()).single;
    expect(reloaded.memberTargets['team-lead'], 'local');
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

  test(
    'createSession seeds remembered mixed-workspace member targets',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'local', 'dev': 'ssh:p1'},
      );

      final session = await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev'),
        ],
      );
      expect(session.memberTargets['team-lead'], 'local');
      expect(session.memberTargets['dev'], 'ssh:p1');
    },
  );

  test(
    'updateWorkspaceMemberPlacement writes targets and init flag together',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      expect(ws.memberPlacementInitializedByTeam['team-a'], isNot(true));

      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'local', 'dev-0': 'local', 'dev-1': 'ssh:p1'},
      );

      final reloaded = (await repo.loadWorkspaces()).single;
      expect(reloaded.memberTargetsByTeam['team-a']?['team-lead'], 'local');
      expect(reloaded.memberTargetsByTeam['team-a']?['dev-0'], 'local');
      expect(reloaded.memberTargetsByTeam['team-a']?['dev-1'], 'ssh:p1');
      expect(reloaded.memberPlacementInitializedByTeam['team-a'], isTrue);
    },
  );

  test(
    'updateWorkspaceMemberTargets does not mark placement initialized',
    () async {
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
        targets: const {'team-lead': 'local'},
      );

      final reloaded = (await repo.loadWorkspaces()).single;
      expect(reloaded.memberTargetsByTeam['team-a']?['team-lead'], 'local');
      expect(reloaded.memberPlacementInitializedByTeam['team-a'], isNot(true));
    },
  );
}
