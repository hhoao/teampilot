import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('listTeammates sorts leader first then member id', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus
      ..declareMember(
        AgentNode.test(
          memberId: 'reviewer',
          displayName: 'Reviewer',
          cli: 'claude',
        ),
      )
      ..declareMember(
        AgentNode.test(
          memberId: 'team-lead',
          displayName: 'Lead',
          cli: 'claude',
          isTeamLead: true,
          lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
        ),
      )
      ..declareMember(
        AgentNode.test(
          memberId: 'developer',
          displayName: 'Dev',
          cli: 'opencode',
        ),
      );

    final roster = bus.listTeammates();

    expect(roster.map((t) => t.memberId), ['team-lead', 'developer', 'reviewer']);
    expect(roster.first.profile.isTeamLead, isTrue);
    expect(roster[1].profile.cli, 'opencode');
  });

  test('fromMember builds Claude-style agentId and agentType', () {
    const team = TeamConfig(
      id: 'my-team',
      name: 'My Team',
      cli: TeamCli.claude,
      teamMode: TeamMode.mixed,
    );
    const member = TeamMemberConfig(
      id: 'developer',
      name: 'Developer',
      agentType: 'implementer',
      model: 'claude-sonnet-4-20250514',
      provider: 'anthropic',
      cli: TeamCli.opencode,
      prompt: 'You implement features.',
    );

    final profile = TeammateRosterProfile.fromMember(
      member: member,
      team: team,
      cliTeamName: 'my-team-1',
      cwd: '/tmp/project',
      taskId: 'task-uuid',
    );

    expect(profile.agentId, 'developer@my-team-1');
    expect(profile.agentType, 'implementer');
    expect(profile.cli, 'opencode');
    expect(profile.taskId, 'task-uuid');
    expect(profile.cwd, '/tmp/project');
  });

  test('listTeammates reports unread mailbox count', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active));
    bus.memberById('leader')!.inbox.deliver(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'),
    );

    expect(bus.listTeammates().single.unreadCount, 1);
  });

  test('declared member with queued mail is mailQueued', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'developer'));
    bus.deliverUserCommand('developer', 'hi');

    final snap = bus.listTeammates().single;
    expect(snap.activity, MemberActivity.mailQueued);
    expect(snap.busPhaseLabel, 'no_pty · mail_queued');
  });

  test('listTeammates reflects waiting flag while blocked in receive', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active));

    final waiting = bus.receive('leader');
    await Future<void>.delayed(Duration.zero);

    final snap = bus.listTeammates().single;
    expect(snap.unreadCount, 0);
    expect(snap.activity, MemberActivity.turnDoneBusWait);
    expect(snap.waitingForMessage, isTrue);

    bus.memberById('leader')!.inbox.deliver(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'),
    );
    final batch = await waiting;
    expect(batch, hasLength(1));
    expect(bus.listTeammates().single.activity, MemberActivity.active);
  });

  test('handler list_teammates includes team header and member fields', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher())
      ..installSessionContext(
        const TeamSessionContext(
          cliTeamName: 'demo-1',
          teamId: 'demo',
          teamName: 'Demo Team',
          description: 'Cross-CLI squad',
          workingDirectory: '/tmp/ws',
          leadAgentId: 'team-lead',
        ),
      );
    bus
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.fromMember(
            member: const TeamMemberConfig(
              id: 'team-lead',
              name: 'Team Lead',
              model: 'claude-opus-4',
              agentType: 'team-lead',
            ),
            team: const TeamConfig(id: 'demo', name: 'Demo Team', teamMode: TeamMode.mixed),
            cliTeamName: 'demo-1',
            cwd: '/tmp/ws',
            taskId: 'lead-task',
          ),
          lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
        ),
      )
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.fromMember(
            member: const TeamMemberConfig(
              id: 'developer',
              name: 'Developer',
              cli: TeamCli.opencode,
              agentType: 'implementer',
            ),
            team: const TeamConfig(id: 'demo', name: 'Demo Team', teamMode: TeamMode.mixed),
            cliTeamName: 'demo-1',
            cwd: '/tmp/ws',
          ),
          lifecycle: MemberLifecycle.declared,
        ),
      );
    bus.memberById('developer')!.inbox.deliver(
      TeamMessage(id: '1', from: 'team-lead', to: 'developer', content: 'hi'),
    );

    final res = await TeammateBusMcpHandler(bus: bus).handle(
      'team-lead',
      const JsonRpcRequest(id: 1, method: 'tools/call', params: {
        'name': 'list_teammates',
        'arguments': {},
      }),
    );

    final text = (res!.result!['content'] as List).first['text'] as String;
    expect(text, contains('=== Team: Demo Team (demo-1) ==='));
    expect(text, contains('description: Cross-CLI squad'));
    expect(text, contains('lead_agent_id: team-lead'));
    expect(text, contains('--- team-lead (self) ---'));
    expect(text, contains('agentId: team-lead'));
    expect(text, contains('model: claude-opus-4'));
    expect(text, contains('taskId: lead-task'));
    expect(text, contains('--- developer ---'));
    expect(text, contains('agentId: developer@demo-1'));
    expect(text, contains('agentType: implementer'));
    expect(text, contains('cli: opencode'));
    expect(text, contains('bus.activity: active'));
    expect(text, contains('bus.phase: in_turn'));
    expect(text, contains('bus.unread: 1'));
    expect(text, contains('pty.running: false'));
  });
}
