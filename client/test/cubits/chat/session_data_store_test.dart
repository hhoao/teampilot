import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

Workspace _ws(String id, {List<String> sessionIds = const []}) => Workspace(
      workspaceId: id,
      folders: [WorkspaceFolder(path: '/$id')],
      createdAt: 0,
      sessionIds: sessionIds,
    );

AppSession _sess(String id, String wsId, {int createdAt = 0}) => AppSession(
      sessionId: id,
      workspaceId: wsId,
      folders: [WorkspaceFolder(path: '/$wsId')],
      createdAt: createdAt,
    );

void main() {
  test('unscoped snapshot exposes all', () {
    final store = SessionDataStore();
    final workspaces = [
      Workspace(
        workspaceId: 'p',
        folders: [WorkspaceFolder(path: '/p')],
        createdAt: 0,
      ),
    ];
    final sessions = [
      AppSession(
        sessionId: 's',
        workspaceId: 'p',
        folders: [WorkspaceFolder(path: '/p')],
        sessionTeam: 't1',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(
      workspaces: workspaces,
      sessions: sessions,
    );
    expect(snap.visibleSessions, sessions);
    expect(snap.visibleWorkspaces, workspaces);
  });

  test(
    'team scope filters sessions by sessionTeam; workspaces stay unscoped',
    () {
      final store = SessionDataStore()
        ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: 't1');
      final workspaces = [
        Workspace(
          workspaceId: 'p1',
          folders: [WorkspaceFolder(path: '/p1')],
          createdAt: 0,
        ),
        Workspace(
          workspaceId: 'p2',
          folders: [WorkspaceFolder(path: '/p2')],
          createdAt: 0,
        ),
      ];
      final sessions = [
        AppSession(
          sessionId: 's1',
          workspaceId: 'p1',
          folders: [WorkspaceFolder(path: '/p1')],
          sessionTeam: 't1',
          createdAt: 0,
        ),
        AppSession(
          sessionId: 's2',
          workspaceId: 'p2',
          folders: [WorkspaceFolder(path: '/p2')],
          sessionTeam: 't2',
          createdAt: 0,
        ),
      ];
      final snap = store.deriveSnapshot(
        workspaces: workspaces,
        sessions: sessions,
      );
      expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s1']);
      expect(snap.visibleWorkspaces, workspaces);
    },
  );

  test('team scope with empty team id shows personal sessions only', () {
    final store = SessionDataStore()
      ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: '');
    final workspaces = [
      Workspace(
        workspaceId: 'personal',
        folders: [WorkspaceFolder(path: '/p')],
        createdAt: 0,
      ),
      Workspace(
        workspaceId: 'team',
        folders: [WorkspaceFolder(path: '/t')],
        createdAt: 0,
      ),
    ];
    final sessions = [
      AppSession(
        sessionId: 'solo',
        workspaceId: 'personal',
        folders: [WorkspaceFolder(path: '/p')],
        sessionTeam: '',
        createdAt: 0,
      ),
      AppSession(
        sessionId: 'team',
        workspaceId: 'team',
        folders: [WorkspaceFolder(path: '/t')],
        sessionTeam: 't1',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(
      workspaces: workspaces,
      sessions: sessions,
    );
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['solo']);
    expect(snap.visibleWorkspaces, workspaces);
  });

  test('sortedSessionIdsByCreatedAt is createdAt desc with stable ties', () {
    final ids = SessionDataStore.sortedSessionIdsByCreatedAt([
      _sess('old', 'p', createdAt: 1),
      _sess('mid', 'p', createdAt: 5),
      _sess('new', 'p', createdAt: 10),
      _sess('tie-a', 'p', createdAt: 5),
      _sess('tie-b', 'p', createdAt: 5),
    ]);
    expect(ids, ['new', 'mid', 'tie-a', 'tie-b', 'old']);
  });

  test('appendSession inserts sessionId into workspace sessionIds (createdAt order)', () {
    final store = SessionDataStore();
    final ws = _ws('p', sessionIds: ['old']);
    final base = store.deriveSnapshot(
      workspaces: [ws],
      sessions: [_sess('old', 'p', createdAt: 1)],
    );
    final snap = store.appendSession(base, _sess('new', 'p', createdAt: 9));
    expect(
      snap.workspaces.single.sessionIds,
      ['new', 'old'],
    );
    expect(snap.sessions.map((s) => s.sessionId), ['old', 'new']);
  });

  test('appendSession is idempotent for an existing session id', () {
    final store = SessionDataStore();
    final ws = _ws('p', sessionIds: ['s1']);
    final base = store.deriveSnapshot(
      workspaces: [ws],
      sessions: [_sess('s1', 'p')],
    );
    final snap = store.appendSession(base, _sess('s1', 'p'));
    expect(snap.workspaces.single.sessionIds, ['s1']);
  });

  test('appendSession for unknown workspace leaves sessionIds untouched', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p')],
      sessions: const [],
    );
    final snap = store.appendSession(base, _sess('orphan', 'other'));
    expect(snap.workspaces.single.sessionIds, isEmpty);
    expect(snap.sessions.single.sessionId, 'orphan');
  });

  test('removeSession removes id from sessions and workspace sessionIds', () {
    final store = SessionDataStore();
    final ws = _ws('p', sessionIds: ['a', 'b']);
    final base = store.deriveSnapshot(
      workspaces: [ws],
      sessions: [_sess('a', 'p'), _sess('b', 'p')],
    );
    final snap = store.removeSession(base, 'a');
    expect(snap.workspaces.single.sessionIds, ['b']);
    expect(snap.sessions.map((s) => s.sessionId), ['b']);
  });

  test('snapshotWithWorkspace replaces workspace but preserves sessionIds', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p', sessionIds: ['a', 'b'])],
      sessions: [_sess('a', 'p'), _sess('b', 'p')],
    );
    final updated = _ws('p').copyWith(display: 'renamed');
    final snap = store.snapshotWithWorkspace(base, updated);
    expect(snap.workspaces.single.display, 'renamed');
    expect(snap.workspaces.single.sessionIds, ['a', 'b']);
  });

  test('snapshotWithWorkspace adds a brand-new workspace', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(workspaces: [_ws('p')], sessions: const []);
    final snap = store.snapshotWithWorkspace(base, _ws('q'));
    expect(snap.workspaces.map((w) => w.workspaceId), ['p', 'q']);
  });

  test('snapshotWithWorkspaceAndSessions replaces workspace sessions and rebuilds sessionIds', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p', sessionIds: ['old'])],
      sessions: [_sess('old', 'p')],
    );
    final snap = store.snapshotWithWorkspaceAndSessions(
      base,
      workspace: _ws('p'),
      sessions: [_sess('n1', 'p', createdAt: 2), _sess('n2', 'p', createdAt: 1)],
    );
    expect(snap.workspaces.single.sessionIds, ['n1', 'n2']);
    expect(snap.sessions.map((s) => s.sessionId), ['n1', 'n2']);
  });

  test('snapshotWithoutWorkspace removes workspace and its sessions', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p'), _ws('q')],
      sessions: [_sess('a', 'p'), _sess('b', 'q')],
    );
    final snap = store.snapshotWithoutWorkspace(base, 'p');
    expect(snap.workspaces.map((w) => w.workspaceId), ['q']);
    expect(snap.sessions.map((s) => s.sessionId), ['b']);
  });
}
