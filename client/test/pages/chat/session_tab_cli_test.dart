import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/session_tab_cli.dart';

void main() {
  ChatTab tab({
    required String id,
    CliTool? sessionCli,
    String memberId = 'team-lead',
    String sessionTeam = '',
    List<SessionMemberBinding> members = const [],
  }) {
    return ChatTab(
        info: ChatTabInfo(id: id, title: id, subtitle: ''),
        cliTeamName: 'team-1',
      )
      ..persistedSession = AppSession(
        sessionId: id,
        workspaceId: 'ws',
        sessionTeam: sessionTeam,
        cli: sessionCli,
        members: members,
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
      tab: tab(id: 's1', memberId: 'coder', sessionTeam: 't1'),
      sessions: const [],
      isPersonal: false,
      team: team,
    );
    expect(resolved, CliTool.cursor);
  });

  test('team tab falls back to team cli for lead', () {
    final resolved = resolveSessionTabCli(
      tab: tab(id: 's1', sessionTeam: 't1'),
      sessions: const [],
      isPersonal: false,
      team: team,
    );
    expect(resolved, CliTool.claude);
  });

  test('team tab prefers binding.cli over live member override', () {
    final liveTeam = TeamProfile(
      id: 't1',
      name: 'Team',
      cli: CliTool.cursor,
      teamMode: TeamMode.mixed,
      members: [
        TeamMemberConfig(id: 'coder', name: 'Coder', cli: CliTool.cursor),
      ],
    );
    final resolved = resolveSessionTabCli(
      tab: tab(
        id: 's1',
        memberId: 'coder',
        sessionTeam: 't1',
        members: [
          SessionMemberBinding(
            rosterMemberId: 'coder',
            taskId: 'task',
            cli: CliTool.claude,
          ),
        ],
      ),
      sessions: const [],
      isPersonal: false,
      team: liveTeam,
    );
    expect(resolved, CliTool.claude);
  });

  test(
    'team tab uses builder-0 binding cli not lead or live type',
    () {
      final replicaTeam = TeamProfile(
        id: 't1',
        name: 'Team',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(
            id: 'builder',
            name: 'Builder',
            cli: CliTool.cursor,
          ),
        ],
      );
      final resolved = resolveSessionTabCli(
        tab: tab(
          id: 's1',
          memberId: 'builder-0',
          sessionTeam: 't1',
          members: [
            SessionMemberBinding(
              rosterMemberId: 'team-lead',
              taskId: 'task-lead',
              cli: CliTool.claude,
            ),
            SessionMemberBinding(
              rosterMemberId: 'builder-0',
              typeId: 'builder',
              taskId: 'task-b0',
              cli: CliTool.opencode,
            ),
          ],
        ),
        sessions: const [],
        isPersonal: false,
        team: replicaTeam,
      );
      expect(resolved, CliTool.opencode);
    },
  );
}
