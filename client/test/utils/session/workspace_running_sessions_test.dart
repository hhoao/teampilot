import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/session/workspace_running_sessions.dart';

void main() {
  group('workspaceRunningSessions', () {
    AppSession session(String id) => AppSession(
      sessionId: id,
      workspaceId: 'ws',
      folders: const [WorkspaceFolder(path: '/a')],
      createdAt: 0,
      updatedAt: 0,
    );

    test('returns working sessions first then listed open-tab sessions', () {
      final sessions = [session('a'), session('b'), session('c')];
      final result = workspaceRunningSessions(
        sessions: sessions,
        workingSessionIds: {'b'},
        openTabSessionIds: {'a', 'c'},
      );
      expect(result.map((s) => s.sessionId), ['b', 'a', 'c']);
    });

    test('returns empty when nothing is running or open', () {
      expect(
        workspaceRunningSessions(
          sessions: [session('a')],
          workingSessionIds: const {},
          openTabSessionIds: const {},
        ),
        isEmpty,
      );
    });
  });
}
