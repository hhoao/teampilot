import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/models/app_workspace.dart';
import 'package:teampilot/models/app_session.dart';

void main() {
  test('unscoped snapshot exposes all', () {
    final store = SessionDataStore();
    final workspaces = [
      Workspace(workspaceId: 'p', primaryPath: '/p', createdAt: 0),
    ];
    final sessions = [
      AppSession(
        sessionId: 's',
        workspaceId: 'p',
        primaryPath: '/p',
        sessionTeam: 't1',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(workspaces: workspaces, sessions: sessions);
    expect(snap.visibleSessions, sessions);
    expect(snap.visibleWorkspaces, workspaces);
  });

  test('team scope filters sessions by sessionTeam; workspaces stay unscoped', () {
    final store = SessionDataStore()
      ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: 't1');
    final workspaces = [
      Workspace(workspaceId: 'p1', primaryPath: '/p1', createdAt: 0),
      Workspace(workspaceId: 'p2', primaryPath: '/p2', createdAt: 0),
    ];
    final sessions = [
      AppSession(
        sessionId: 's1',
        workspaceId: 'p1',
        primaryPath: '/p1',
        sessionTeam: 't1',
        createdAt: 0,
      ),
      AppSession(
        sessionId: 's2',
        workspaceId: 'p2',
        primaryPath: '/p2',
        sessionTeam: 't2',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(workspaces: workspaces, sessions: sessions);
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s1']);
    expect(snap.visibleWorkspaces, workspaces);
  });

  test('team scope with empty team id shows personal sessions only', () {
    final store = SessionDataStore()
      ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: '');
    final workspaces = [
      Workspace(workspaceId: 'personal', primaryPath: '/p', createdAt: 0),
      Workspace(workspaceId: 'team', primaryPath: '/t', createdAt: 0),
    ];
    final sessions = [
      AppSession(
        sessionId: 'solo',
        workspaceId: 'personal',
        primaryPath: '/p',
        sessionTeam: '',
        createdAt: 0,
      ),
      AppSession(
        sessionId: 'team',
        workspaceId: 'team',
        primaryPath: '/t',
        sessionTeam: 't1',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(workspaces: workspaces, sessions: sessions);
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['solo']);
    expect(snap.visibleWorkspaces, workspaces);
  });
}
