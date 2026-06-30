import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/session_tab_cli.dart';

void main() {
  ChatTab tab({
    required String id,
    CliTool? sessionCli,
    String memberId = 'team-lead',
  }) {
    return ChatTab(
      info: ChatTabInfo(id: id, title: id, subtitle: ''),
      cliTeamName: 'team-1',
    )
      ..persistedSession = AppSession(
        sessionId: id,
        workspaceId: 'ws',
        cli: sessionCli,
        createdAt: 0,
      )
      ..selectedMemberId = memberId;
  }

  final team = TeamProfile(
    id: 't1',
    name: 'Team',
    cli: CliTool.claude,
    teamMode: TeamMode.mixed,
    members: [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'coder', name: 'Coder', cli: CliTool.cursor),
    ],
  );

  test('personal tab uses session cli when pinned', () {
    final resolved = resolveSessionTabCli(
      tab: tab(id: 's1', sessionCli: CliTool.codex),
      sessions: const [],
      isPersonal: true,
      personalFallbackCli: CliTool.opencode,
    );
    expect(resolved, CliTool.codex);
  });

  test('personal tab falls back to active preset cli', () {
    final resolved = resolveSessionTabCli(
      tab: tab(id: 's1'),
      sessions: const [],
      isPersonal: true,
      personalFallbackCli: CliTool.opencode,
    );
    expect(resolved, CliTool.opencode);
  });

  test('team tab uses selected member cli override in mixed mode', () {
    final resolved = resolveSessionTabCli(
      tab: tab(id: 's1', memberId: 'coder'),
      sessions: const [],
      isPersonal: false,
      team: team,
    );
    expect(resolved, CliTool.cursor);
  });

  test('team tab falls back to team cli for lead', () {
    final resolved = resolveSessionTabCli(
      tab: tab(id: 's1'),
      sessions: const [],
      isPersonal: false,
      team: team,
    );
    expect(resolved, CliTool.claude);
  });
}
