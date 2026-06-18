import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/utils/workspace_sessions.dart';

void main() {
  const fallback = 'New chat';

  AppSession session({
    required String id,
    required String workspaceId,
    String display = '',
  }) {
    return AppSession(
      sessionId: id,
      workspaceId: workspaceId,
      primaryPath: '/tmp',
      display: display,
      createdAt: 1,
    );
  }

  test('sessionsForWorkspace preserves workspace.sessionIds order', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp',
      sessionIds: const ['s2', 's1'],
      createdAt: 1,
    );
    final all = [
      session(id: 's1', workspaceId: 'p1', display: 'Alpha'),
      session(id: 's2', workspaceId: 'p1', display: 'Beta'),
      session(id: 's3', workspaceId: 'p2', display: 'Other'),
    ];

    final ordered = sessionsForWorkspace(workspace, all);

    expect(ordered.map((s) => s.sessionId).toList(), ['s2', 's1']);
  });

  test('sessionsForWorkspace appends orphan sessions without duplicates', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp',
      sessionIds: const ['s1'],
      createdAt: 1,
    );
    final all = [
      session(id: 's1', workspaceId: 'p1', display: 'Listed'),
      session(id: 's2', workspaceId: 'p1', display: 'Orphan'),
      session(id: 's3', workspaceId: 'p2', display: 'Other'),
    ];

    final ordered = sessionsForWorkspace(workspace, all);

    expect(ordered.map((s) => s.sessionId).toList(), ['s1', 's2']);
  });

  test('filterSessionsByQuery matches display title case-insensitively', () {
    final sessions = [
      session(id: 's1', workspaceId: 'p1', display: 'Fix Login Bug'),
      session(id: 's2', workspaceId: 'p1', display: 'Docs'),
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
      session(id: 'abc-123', workspaceId: 'p1'),
      session(id: 'xyz-999', workspaceId: 'p1'),
    ];

    final filtered = filterSessionsByQuery(
      sessions,
      query: 'abc',
      emptyTitleFallback: fallback,
    );

    expect(filtered.map((s) => s.sessionId).toList(), ['abc-123']);
  });

  test('groupSessionsByWorkspaceId buckets sessions by workspaceId', () {
    final all = [
      session(id: 's1', workspaceId: 'p1'),
      session(id: 's2', workspaceId: 'p1'),
      session(id: 's3', workspaceId: 'p2'),
    ];

    final grouped = groupSessionsByWorkspaceId(all);

    expect(grouped['p1']!.map((s) => s.sessionId).toList(), ['s1', 's2']);
    expect(grouped['p2']!.map((s) => s.sessionId).toList(), ['s3']);
  });

  test('filterSessionsByQuery returns all sessions when query is blank', () {
    final sessions = [
      session(id: 's1', workspaceId: 'p1', display: 'One'),
      session(id: 's2', workspaceId: 'p1', display: 'Two'),
    ];

    final filtered = filterSessionsByQuery(
      sessions,
      query: '   ',
      emptyTitleFallback: fallback,
    );

    expect(filtered, sessions);
  });
}
