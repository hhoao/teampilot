import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/session_chat_continue_seat.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

void main() {
  const lead = TeamMemberConfig(id: 'team-lead', name: 'Lead');
  const developer = TeamMemberConfig(
    id: 'developer',
    name: 'Developer',
    replicas: 2,
  );
  const team = TeamProfile(
    id: 't1',
    name: 'Team',
    teamMode: TeamMode.mixed,
    members: [lead, developer],
  );

  AppSession sessionWithInstances(List<String> instanceIds) {
    return AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: team.id,
      members: [
        for (final id in instanceIds)
          SessionMemberBinding(
            rosterMemberId: id,
            taskId: 'task-$id',
            typeId: id.startsWith('developer-') ? 'developer' : id,
          ),
      ],
      createdAt: 1,
    );
  }

  group('resolveSessionChatContinueMember', () {
    test('resolves numbered instance id from session roster', () {
      final session = sessionWithInstances([
        'team-lead',
        'developer-0',
        'developer-1',
      ]);

      final member = resolveSessionChatContinueMember(
        session: session,
        team: team,
        selectedMemberId: 'developer-0',
      );

      expect(member?.id, 'developer-0');
    });

    test('resolves second replica without falling back to lead', () {
      final session = sessionWithInstances([
        'team-lead',
        'developer-0',
        'developer-1',
      ]);

      final member = resolveSessionChatContinueMember(
        session: session,
        team: team,
        selectedMemberId: 'developer-1',
      );

      expect(member?.id, 'developer-1');
      expect(TeamMemberNaming.isTeamLead(member!), isFalse);
    });

    test('resolves singleton type id from team members', () {
      const singletonDev = TeamMemberConfig(id: 'developer', name: 'Developer');
      const singletonTeam = TeamProfile(
        id: 't2',
        name: 'Team',
        teamMode: TeamMode.mixed,
        members: [lead, singletonDev],
      );
      final session = AppSession(
        sessionId: 's2',
        workspaceId: 'w1',
        sessionTeam: singletonTeam.id,
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'team-lead',
            taskId: 'tl',
            typeId: 'team-lead',
          ),
          SessionMemberBinding(
            rosterMemberId: 'developer',
            taskId: 'dev',
            typeId: 'developer',
          ),
        ],
        createdAt: 1,
      );

      final member = resolveSessionChatContinueMember(
        session: session,
        team: singletonTeam,
        selectedMemberId: 'developer',
      );

      expect(member?.id, 'developer');
    });

    test('empty selection defaults to team lead', () {
      final session = sessionWithInstances(['team-lead', 'developer-0']);

      final member = resolveSessionChatContinueMember(
        session: session,
        team: team,
        selectedMemberId: '',
      );

      expect(member?.id, 'team-lead');
    });

    test('unknown selection does not retarget to lead', () {
      final session = sessionWithInstances(['team-lead', 'developer-0']);

      final member = resolveSessionChatContinueMember(
        session: session,
        team: team,
        selectedMemberId: 'ghost-0',
      );

      expect(member, isNull);
    });

    test('uses runtime roster when session has no bindings yet', () {
      final session = AppSession(
        sessionId: 's3',
        workspaceId: 'w1',
        sessionTeam: team.id,
        createdAt: 1,
      );

      final member = resolveSessionChatContinueMember(
        session: session,
        team: team,
        selectedMemberId: 'developer-1',
      );

      expect(member?.id, 'developer-1');
    });
  });
}
