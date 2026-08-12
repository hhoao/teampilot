import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/workspace_catalog.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

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
}
