import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_list_entry.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('fromSession keeps list fields and toListSession drops folders', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      display: 'Hello',
      sessionTeam: 't1',
      folders: [WorkspaceFolder(path: '/repo')],
      createdAt: 10,
      updatedAt: 20,
      archived: true,
      pinned: true,
      sortOrder: 3,
      purpose: SessionPurpose.teamGeneration,
      workflowId: 'wf',
    );
    final entry = SessionListEntry.fromSession(session);
    expect(entry.sessionId, 's1');
    expect(entry.display, 'Hello');
    expect(entry.sessionTeam, 't1');
    expect(entry.archived, isTrue);
    expect(entry.pinned, isTrue);
    expect(entry.sortOrder, 3);
    expect(entry.purpose, SessionPurpose.teamGeneration);
    expect(entry.workflowId, 'wf');
    final list = entry.toListSession('w1');
    expect(list.display, 'Hello');
    expect(list.folders, isEmpty);
    expect(list.members, isEmpty);
    expect(list.archived, isTrue);
  });

  test('round-trips json including unknown-purpose fail-closed to normal', () {
    final entry = SessionListEntry.fromJson({
      'sessionId': 's',
      'display': 'd',
      'purpose': 'not-a-purpose',
      'createdAt': 1,
    });
    expect(entry.purpose, SessionPurpose.normal);
    expect(SessionListEntry.fromJson(entry.toJson()).sessionId, 's');
  });
}
