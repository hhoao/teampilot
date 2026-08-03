import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/runtime_roster_cache.dart';

TeamProfile team(List<TeamMemberConfig> members) => TeamProfile(
  id: 'team-1',
  name: 'T',
  cli: CliTool.claude,
  teamMode: TeamMode.mixed,
  members: members,
);

void main() {
  test('singleton type → one instance whose id is the type id', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ]);
    expect(insts.single.instanceId, 'builder');
    expect(insts.single.displayName, 'Builder');
  });

  test('replicated type → N numbered instances', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 3),
    ]);
    expect(insts.map((i) => i.instanceId), [
      'builder-0',
      'builder-1',
      'builder-2',
    ]);
    expect(insts.map((i) => i.displayName), [
      'Builder #0',
      'Builder #1',
      'Builder #2',
    ]);
  });

  test('the team-lead is always a singleton regardless of replicas', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead', replicas: 5),
    ]);
    expect(insts.single.instanceId, 'team-lead');
  });

  test('non-lead replicas 0 yields no instances', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 0),
    ]);
    expect(insts, isEmpty);
  });

  test('lead with replicas 0 still yields one instance', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead', replicas: 0),
    ]);
    expect(insts.single.instanceId, 'team-lead');
  });

  test('workspaceion seeds agentType from type id when empty', () {
    final cfg = expandTeamRoster(const [
      TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
    ]).first.toMemberConfig();
    expect(cfg.id, 'developer-0');
    expect(cfg.agentType, 'developer');
  });

  test('workspaceion preserves explicit type.agentType', () {
    final cfg = expandTeamRoster(const [
      TeamMemberConfig(
        id: 'developer',
        name: 'Developer',
        replicas: 2,
        agentType: 'implementer',
      ),
    ]).first.toMemberConfig();
    expect(cfg.agentType, 'implementer');
  });

  test('workspaceion seeds agentType from type.agent when agentType empty', () {
    final cfg = expandTeamRoster(const [
      TeamMemberConfig(
        id: 'developer',
        name: 'Developer',
        replicas: 2,
        agent: 'coder',
      ),
    ]).first.toMemberConfig();
    expect(cfg.agentType, 'coder');
  });

  test('workspaceion seeds the type id as a capability', () {
    final inst = expandTeamRoster(const [
      TeamMemberConfig(
        id: 'builder',
        name: 'Builder',
        replicas: 2,
        capabilities: {'rust'},
      ),
    ]).first;
    final cfg = inst.toMemberConfig();
    expect(cfg.id, 'builder-0');
    expect(cfg.capabilities, {'builder', 'rust'});
    // a workspaceion is a single concrete pod, not itself re-expandable
    expect(cfg.replicas, 1);
  });

  test('runtimeRosterMembers workspaces every instance', () {
    final members = runtimeRosterMembers(
      team(const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
      ]),
    );
    expect(members.map((m) => m.id), ['team-lead', 'builder-0', 'builder-1']);
  });

  test('sessionRosterMembers keeps only session-bound instances', () {
    final profile = team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      members: const [
        SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't1'),
        SessionMemberBinding(rosterMemberId: 'builder-1', taskId: 't2'),
      ],
    );
    expect(
      sessionRosterMembers(session, profile).map((m) => m.id),
      ['team-lead', 'builder-1'],
    );
  });

  test(
    'sessionRosterMembers materializes bindings when team replicas are stale',
    () {
      // createSession heals expansion from workspace pins, but LaunchProfileCubit
      // may still hold replicas=1 until reload — bus/UI must trust session pods.
      final profile = team(const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
      ]);
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
        members: const [
          SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't1'),
          SessionMemberBinding(
            rosterMemberId: 'builder-0',
            taskId: 't2',
            typeId: 'builder',
          ),
          SessionMemberBinding(
            rosterMemberId: 'builder-1',
            taskId: 't3',
            typeId: 'builder',
          ),
        ],
      );
      final ids = sessionRosterMembers(session, profile).map((m) => m.id);
      expect(ids, ['team-lead', 'builder-0', 'builder-1']);
      expect(
        sessionRosterMembers(session, profile).map((m) => m.name),
        ['team-lead', 'Builder #0', 'Builder #1'],
      );
    },
  );

  test('cliTeamRosterMembers matches sessionRosterMembers', () {
    final profile = team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
      TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
    ]);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      members: const [
        SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't0'),
        SessionMemberBinding(
          rosterMemberId: 'developer-0',
          typeId: 'developer',
          taskId: 't1',
        ),
        SessionMemberBinding(
          rosterMemberId: 'developer-1',
          typeId: 'developer',
          taskId: 't2',
        ),
      ],
    );
    final cli = cliTeamRosterMembers(session, profile);
    final ui = sessionRosterMembers(session, profile);
    expect(cli.map((m) => m.id), ui.map((m) => m.id));
    expect(cli.map((m) => m.id), ['team-lead', 'developer-0', 'developer-1']);
    expect(cli.map((m) => m.agentType), ['team-lead', 'developer', 'developer']);
  });

  test('singleton replica keeps bare type id', () {
    final profile = team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 1),
    ]);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      members: const [
        SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't0'),
        SessionMemberBinding(rosterMemberId: 'developer', taskId: 't1'),
      ],
    );
    expect(
      cliTeamRosterMembers(session, profile).map((m) => m.id),
      ['team-lead', 'developer'],
    );
  });

  test(
    'sessionRosterMembers infers type from numbered instance id without typeId',
    () {
      final profile = team(const [
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
      ]);
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
        members: const [
          SessionMemberBinding(rosterMemberId: 'builder-0', taskId: 't1'),
          SessionMemberBinding(rosterMemberId: 'builder-1', taskId: 't2'),
        ],
      );
      expect(
        sessionRosterMembers(session, profile).map((m) => m.id),
        ['builder-0', 'builder-1'],
      );
    },
  );

  test('RuntimeRosterCache returns the same list for the same team', () {
    final cache = RuntimeRosterCache();
    final profile = team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]);

    final first = cache.resolve(profile);
    final second = cache.resolve(profile);
    expect(identical(first, second), isTrue);
  });

  test('RuntimeRosterCache clears when replicas change', () {
    final cache = RuntimeRosterCache();
    final base = team(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
    ]);
    final expanded = team(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]);

    expect(cache.resolve(base), hasLength(1));
    cache.clear();
    expect(cache.resolve(expanded), hasLength(2));
  });
}
