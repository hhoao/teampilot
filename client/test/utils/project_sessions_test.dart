import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/utils/project_sessions.dart';

void main() {
  const fallback = 'New chat';

  AppSession session({
    required String id,
    required String projectId,
    String display = '',
  }) {
    return AppSession(
      sessionId: id,
      projectId: projectId,
      primaryPath: '/tmp',
      display: display,
      createdAt: 1,
    );
  }

  test('sessionsForProject preserves project.sessionIds order', () {
    final project = AppProject(
      projectId: 'p1',
      primaryPath: '/tmp',
      sessionIds: const ['s2', 's1'],
      createdAt: 1,
    );
    final all = [
      session(id: 's1', projectId: 'p1', display: 'Alpha'),
      session(id: 's2', projectId: 'p1', display: 'Beta'),
      session(id: 's3', projectId: 'p2', display: 'Other'),
    ];

    final ordered = sessionsForProject(project, all);

    expect(ordered.map((s) => s.sessionId).toList(), ['s2', 's1']);
  });

  test('filterSessionsByQuery matches display title case-insensitively', () {
    final sessions = [
      session(id: 's1', projectId: 'p1', display: 'Fix Login Bug'),
      session(id: 's2', projectId: 'p1', display: 'Docs'),
    ];

    final filtered = filterSessionsByQuery(
      sessions,
      query: 'login',
      emptyTitleFallback: fallback,
    );

    expect(filtered.map((s) => s.sessionId).toList(), ['s1']);
  });

  test('filterSessionsByQuery matches session id', () {
    final sessions = [
      session(id: 'abc-123', projectId: 'p1'),
      session(id: 'xyz-999', projectId: 'p1'),
    ];

    final filtered = filterSessionsByQuery(
      sessions,
      query: 'abc',
      emptyTitleFallback: fallback,
    );

    expect(filtered.map((s) => s.sessionId).toList(), ['abc-123']);
  });

  test('filterSessionsByQuery returns all sessions when query is blank', () {
    final sessions = [
      session(id: 's1', projectId: 'p1', display: 'One'),
      session(id: 's2', projectId: 'p1', display: 'Two'),
    ];

    final filtered = filterSessionsByQuery(
      sessions,
      query: '   ',
      emptyTitleFallback: fallback,
    );

    expect(filtered, sessions);
  });
}
