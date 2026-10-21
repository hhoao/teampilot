import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_list_entry.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';

void main() {
  test('fromSession keeps list fields and folder metadata', () {
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
    expect(list.folders.single.path, '/repo');
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

  test(
    'carries the persisted ACP flag and CLI so a stub is not judged PTY',
    () {
      final acp = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        display: 'ACP',
        cli: CliTool.claude,
        acp: true,
        createdAt: 10,
      );
      final acpEntry = SessionListEntry.fromSession(acp);
      expect(acpEntry.acp, isTrue);
      expect(acpEntry.cli, CliTool.claude);

      final acpStub = acpEntry.toListSession('w1');
      expect(acpStub.acp, isTrue);
      expect(acpStub.cli, CliTool.claude);
      expect(isAcpChatSession(acpStub), isTrue);

      final roundTripped = SessionListEntry.fromJson(acpEntry.toJson());
      expect(roundTripped.acp, isTrue);
      expect(roundTripped.cli, CliTool.claude);
      expect(isAcpChatSession(roundTripped.toListSession('w1')), isTrue);

      final pty = AppSession(
        sessionId: 's2',
        workspaceId: 'w1',
        display: 'PTY',
        cli: CliTool.claude,
        createdAt: 11,
      );
      final ptyEntry = SessionListEntry.fromSession(pty);
      expect(ptyEntry.acp, isFalse);
      expect(ptyEntry.toJson()['acp'], isFalse);

      final legacy = SessionListEntry.fromJson({
        'sessionId': 's3',
        'display': 'legacy',
        'createdAt': 1,
      });
      expect(legacy.acp, isFalse);
      expect(legacy.cli, isNull);
    },
  );
}
