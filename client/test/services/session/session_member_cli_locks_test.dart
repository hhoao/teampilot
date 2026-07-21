import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_member_cli_locks.dart';

void main() {
  group('resolveSessionMemberCliLocks', () {
    test('returns one entry per valid roster type, not expanded instances', () {
      const team = TeamProfile(
        id: 't1',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(id: 'lead', name: 'Lead'),
          TeamMemberConfig(
            id: 'builder',
            name: 'Builder',
            cli: CliTool.codex,
            replicas: 2,
          ),
          TeamMemberConfig(id: 'ghost', name: '   '),
        ],
      );

      final locks = resolveSessionMemberCliLocks(
        team: team,
        rosterMembers: team.members,
      );

      expect(locks.keys.toSet(), {'lead', 'builder'});
      expect(locks['lead'], CliTool.claude);
      expect(locks['builder'], CliTool.codex);
      expect(locks.containsKey('builder-0'), isFalse);
      expect(locks.containsKey('builder-1'), isFalse);
    });

    test('mixed member with explicit cli locks that tool, not team default', () {
      const team = TeamProfile(
        id: 't1',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(
            id: 'worker',
            name: 'Worker',
            cli: CliTool.cursor,
          ),
        ],
      );

      final locks = resolveSessionMemberCliLocks(
        team: team,
        rosterMembers: team.members,
      );

      expect(locks, {'worker': CliTool.cursor});
    });

    test('keys use type id builder, never builder-0 instance ids', () {
      const team = TeamProfile(
        id: 't1',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],
      );

      final locks = resolveSessionMemberCliLocks(
        team: team,
        rosterMembers: team.members,
      );

      expect(locks.keys, ['builder']);
      expect(locks.containsKey('builder-0'), isFalse);
    });
  });

  group('copyCliFromSourceBinding', () {
    test('prefers same rosterMemberId, else any same typeId, else null', () {
      const source = [
        SessionMemberBinding(
          rosterMemberId: 'builder-0',
          taskId: 't0',
          typeId: 'builder',
          cli: CliTool.cursor,
        ),
        SessionMemberBinding(
          rosterMemberId: 'builder-1',
          taskId: 't1',
          typeId: 'builder',
          cli: CliTool.codex,
        ),
        SessionMemberBinding(
          rosterMemberId: 'reviewer',
          taskId: 't2',
          typeId: 'reviewer',
          cli: CliTool.claude,
        ),
      ];

      expect(
        copyCliFromSourceBinding(
          sourceMembers: source,
          rosterMemberId: 'builder-1',
          typeId: 'builder',
        ),
        CliTool.codex,
      );

      expect(
        copyCliFromSourceBinding(
          sourceMembers: source,
          rosterMemberId: 'builder-9',
          typeId: 'builder',
        ),
        CliTool.cursor,
      );

      expect(
        copyCliFromSourceBinding(
          sourceMembers: source,
          rosterMemberId: 'missing',
          typeId: 'unknown',
        ),
        isNull,
      );
    });
  });
}
