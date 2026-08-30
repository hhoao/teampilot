import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/utils/session/session_archive_filter.dart';

AppSession _s(String id, {bool archived = false}) => AppSession(
      sessionId: id,
      workspaceId: 'w',
      createdAt: 1,
      archived: archived,
    );

void main() {
  test('activeSessions excludes archived', () {
    final all = [_s('a'), _s('b', archived: true), _s('c')];
    expect(activeSessions(all).map((s) => s.sessionId), ['a', 'c']);
  });

  test('archivedSessions keeps only archived', () {
    final all = [_s('a'), _s('b', archived: true)];
    expect(archivedSessions(all).map((s) => s.sessionId), ['b']);
  });
}
