import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/terminal/session_member_cli_resolver.dart';

void main() {
  group('SessionMemberCliResolver', () {
    CliTool cliForMember(
      TeamProfile team,
      String memberId, {
      List<CliPreset> globalPresets = const [],
    }) {
      for (final m in team.members) {
        if (m.id == memberId) return m.cli ?? team.cli;
      }
      return team.cli;
    }

    test('personal session uses pinned cli', () {
      final cli = SessionMemberCliResolver.resolve(
        persistedSession: AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          cli: CliTool.cursor,
          createdAt: 1,
        ),
        team: null,
        memberId: 'solo',
        cliForMember: cliForMember,
      );

      expect(cli, CliTool.cursor);
    });

    test('personal session without pinned cli falls back to claude', () {
      final cli = SessionMemberCliResolver.resolve(
        persistedSession: AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          createdAt: 1,
        ),
        team: null,
        memberId: 'solo',
        cliForMember: cliForMember,
      );

      expect(cli, CliTool.claude);
    });

    test('team session resolves member override', () {
      final team = TeamProfile(
        id: 't1',
        name: 'Team',
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(
            id: 'worker',
            name: 'Worker',
            cli: CliTool.cursor,
          ),
        ],
      );

      final cli = SessionMemberCliResolver.resolve(
        persistedSession: AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          sessionTeam: 't1',
          createdAt: 1,
        ),
        team: team,
        memberId: 'worker',
        cliForMember: cliForMember,
      );

      expect(cli, CliTool.cursor);
    });

    test('team session falls back to team cli for unknown member', () {
      final team = TeamProfile(
        id: 't1',
        name: 'Team',
        cli: CliTool.codex,
        members: const [],
      );

      final cli = SessionMemberCliResolver.resolve(
        persistedSession: AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          sessionTeam: 't1',
          createdAt: 1,
        ),
        team: team,
        memberId: 'missing',
        cliForMember: cliForMember,
      );

      expect(cli, CliTool.codex);
    });
  });
}
