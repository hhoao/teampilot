import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/workspace_catalog.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/workspace_index_store.dart';

void main() {
  WorkspaceCatalog buildCatalog() {
    final catalog = WorkspaceCatalog(SessionRepository()); // 本组测试不触 repo
    catalog.ingest(
      workspaces: [Workspace(workspaceId: 'p', folders: [WorkspaceFolder(path: '/p')], createdAt: 0)],
      sessions: [AppSession(sessionId: 's', workspaceId: 'p', folders: [WorkspaceFolder(path: '/p')], sessionTeam: 't1', createdAt: 0)],
    );
    return catalog;
  }

  test('unscoped snapshot exposes all', () {
    final snap = buildCatalog().deriveSnapshot();
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s']);
    expect(snap.visibleWorkspaces.map((w) => w.workspaceId).toList(), ['p']);
  });

  test('team scope filters sessions by sessionTeam; workspaces stay unscoped', () {
    final catalog = buildCatalog()..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: 't1');
    final snap = catalog.deriveSnapshot();
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s']);
  });

  test('team scope with empty team id shows personal sessions only', () {
    final catalog = buildCatalog()..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: '');
    expect(catalog.deriveSnapshot().visibleSessions, isEmpty);
  });

  test('workspaceById/sessionById/sessionsLoadedForWorkspace', () {
    final catalog = buildCatalog();
    expect(catalog.workspaceById('p')?.workspaceId, 'p');
    expect(catalog.sessionById('s')?.sessionId, 's');
    expect(catalog.sessionsLoadedForWorkspace('p'), true);
    expect(catalog.sessionById('nope'), isNull);
  });

  test('snapshot visible lists are unmodifiable copies, not memory aliases', () {
    final catalog = buildCatalog();
    final snap = catalog.deriveSnapshot();
    expect(() => snap.visibleSessions.add(AppSession(
          sessionId: 'x',
          workspaceId: 'p',
          folders: [WorkspaceFolder(path: '/p')],
          createdAt: 0,
        )), throwsUnsupportedError);
    expect(catalog.sessions.length, 1);
  });

  test('createWorkspaceWithFirstSession does not full-scan', () async {
    final tmp = await Directory.systemTemp.createTemp('catalog_create_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final catalog = WorkspaceCatalog(repo);
    await catalog.loadIndex();
    final result = await catalog.createWorkspaceWithFirstSession(
      [const WorkspaceFolder(path: '/proj')],
      display: 'P',
    );
    expect(result.workspaceId, isNotEmpty);
    expect(catalog.workspaceById(result.workspaceId), isNotNull);
    expect(await catalog.sessionsForWorkspace(result.workspaceId), isNotEmpty);
    final fs = await repo.fs();
    final index = await WorkspaceIndexStore(fs).tryRead(preferIsolate: false);
    expect(index?.map((w) => w.workspaceId), contains(result.workspaceId));
    // Wait out the fire-and-forget trust provision so tearDown can delete
    // the temp root (Windows blocks deletion of open files, errno=32).
    await catalog.trustProvisioningFor(result.workspaceId);
  });

  test('createWorkspaceWithFirstSession dedups in memory when allowDuplicate false', () async {
    final tmp = await Directory.systemTemp.createTemp('catalog_dedup_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final catalog = WorkspaceCatalog(repo);
    await catalog.loadIndex();
    final a = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/dup')]);
    final b = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/dup')]);
    expect(a.workspaceId, b.workspaceId);
    expect(catalog.workspaces.length, 1);
    await catalog.trustProvisioningFor(a.workspaceId);
  });

  test('renameSession patches memory and disk', () async {
    final tmp = await Directory.systemTemp.createTemp('catalog_rename_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final catalog = WorkspaceCatalog(repo);
    await catalog.loadIndex();
    final ws = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/p')]);
    final created = await catalog.createSession(ws.workspaceId);
    final snap = await catalog.renameSession(created.session.sessionId, 'New Title');
    expect(snap.sessions.firstWhere((s) => s.sessionId == created.session.sessionId).display, 'New Title');
    expect(catalog.sessionById(created.session.sessionId)?.display, 'New Title');
    final fs = await repo.fs();
    final raw = await fs.readText(fs.sessionFile(ws.workspaceId, created.session.sessionId));
    expect(jsonDecode(raw!)['display'], 'New Title');
    await catalog.trustProvisioningFor(ws.workspaceId);
  });

  test('createWorkspaceWithFirstSession persists team pins into catalog memory', () async {
    final tmp = await Directory.systemTemp.createTemp('catalog_team_pins_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final catalog = WorkspaceCatalog(repo);
    await catalog.loadIndex();
    final result = await catalog.createWorkspaceWithFirstSession(
      [const WorkspaceFolder(path: '/teamproj')],
      sessionTeamId: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
      memberClis: const {'team-lead': CliTool.claude},
    );
    expect(
      catalog.workspaceById(result.workspaceId)?.memberTargetsByTeam['team-a'],
      {'team-lead': 'local'},
    );
    final onDisk = (await repo.loadWorkspaces()).single;
    expect(onDisk.memberTargetsByTeam['team-a'], {'team-lead': 'local'});
    await catalog.trustProvisioningFor(result.workspaceId);
  });

  test('createWorkspaceWithFirstSession dedup merge resets placement init in memory', () async {
    final tmp = await Directory.systemTemp.createTemp('catalog_mix_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final catalog = WorkspaceCatalog(repo);
    await catalog.loadIndex();
    final ws = await repo.createWorkspace([const WorkspaceFolder(path: '/mix')]);
    await repo.updateWorkspaceMemberTargets(
      ws.workspaceId,
      'team-a',
      targets: const {'m': 'local'},
    );
    await repo.updateWorkspaceMemberPlacement(
      ws.workspaceId,
      'team-a',
      targets: const {'m': 'local'},
    );
    await catalog.reload();
    expect(
      catalog.workspaceById(ws.workspaceId)?.memberPlacementInitializedByTeam['team-a'],
      isTrue,
    );
    final result = await catalog.createWorkspaceWithFirstSession([
      const WorkspaceFolder(path: '/mix'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:r1'),
    ]);
    expect(result.workspaceId, ws.workspaceId);
    final merged = catalog.workspaceById(ws.workspaceId);
    expect(merged?.folders.length, 2);
    expect(merged?.memberPlacementInitializedByTeam['team-a'], isFalse);
    final onDisk = (await repo.loadWorkspaces()).single;
    expect(onDisk.memberPlacementInitializedByTeam['team-a'], isFalse);
    await catalog.trustProvisioningFor(result.workspaceId);
  });

  test('renameSession bumps updatedAt in memory', () async {
    final tmp = await Directory.systemTemp.createTemp('catalog_rename_ts_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final catalog = WorkspaceCatalog(repo);
    await catalog.loadIndex();
    final ws = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/p')]);
    final created = await catalog.createSession(ws.workspaceId);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final before = catalog.sessionById(created.session.sessionId)!.updatedAt;
    expect(before, isNonZero);
    final snap = await catalog.renameSession(created.session.sessionId, 'Renamed');
    final after = catalog.sessionById(created.session.sessionId)!.updatedAt;
    expect(after, greaterThan(before));
    expect(
      snap.sessions.firstWhere((s) => s.sessionId == created.session.sessionId).updatedAt,
      after,
    );
  });
}
