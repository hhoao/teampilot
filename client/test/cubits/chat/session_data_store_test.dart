import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';

void main() {
  test('unscoped snapshot exposes all', () {
    final store = SessionDataStore();
    final projects = [
      AppProject(projectId: 'p', primaryPath: '/p', createdAt: 0),
    ];
    final sessions = [
      AppSession(
        sessionId: 's',
        projectId: 'p',
        primaryPath: '/p',
        sessionTeam: 't1',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(projects: projects, sessions: sessions);
    expect(snap.visibleSessions, sessions);
    expect(snap.visibleProjects, projects);
  });

  test('team scope filters sessions by sessionTeam; projects stay unscoped', () {
    final store = SessionDataStore()
      ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: 't1');
    final projects = [
      AppProject(projectId: 'p1', primaryPath: '/p1', createdAt: 0),
      AppProject(projectId: 'p2', primaryPath: '/p2', createdAt: 0),
    ];
    final sessions = [
      AppSession(
        sessionId: 's1',
        projectId: 'p1',
        primaryPath: '/p1',
        sessionTeam: 't1',
        createdAt: 0,
      ),
      AppSession(
        sessionId: 's2',
        projectId: 'p2',
        primaryPath: '/p2',
        sessionTeam: 't2',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(projects: projects, sessions: sessions);
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s1']);
    expect(snap.visibleProjects, projects);
  });

  test('team scope with empty team id shows personal sessions only', () {
    final store = SessionDataStore()
      ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: '');
    final projects = [
      AppProject(projectId: 'personal', primaryPath: '/p', createdAt: 0),
      AppProject(projectId: 'team', primaryPath: '/t', createdAt: 0),
    ];
    final sessions = [
      AppSession(
        sessionId: 'solo',
        projectId: 'personal',
        primaryPath: '/p',
        sessionTeam: '',
        createdAt: 0,
      ),
      AppSession(
        sessionId: 'team',
        projectId: 'team',
        primaryPath: '/t',
        sessionTeam: 't1',
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(projects: projects, sessions: sessions);
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['solo']);
    expect(snap.visibleProjects, projects);
  });
}
