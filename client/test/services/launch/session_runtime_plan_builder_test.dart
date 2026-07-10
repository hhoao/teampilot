import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_capability_pack.dart';
import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/launch/session_runtime_plan_builder.dart';

void main() {
  late _FakeExpertResolver resolver;
  late Map<String, ConfigBundle> workspaceBundles;
  late SessionRuntimePlanBuilder builder;

  setUp(() {
    resolver = _FakeExpertResolver();
    workspaceBundles = {};
    builder = SessionRuntimePlanBuilder(
      expertResolver: resolver,
      loadWorkspaceBundle: (workspaceId) async {
        return workspaceBundles[workspaceId] ?? const ConfigBundle();
      },
    );
  });

  test('simple plan merges expert over workspace', () async {
    resolver.packs['ex-key'] = ExpertCapabilityPack(
      member: const TeamMemberConfig(id: 'ex', name: 'Expert'),
      bundle: const ConfigBundle(skillIds: ['ex']),
    );
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['ws']);

    final plan = await builder.buildSimple(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      memberId: 'seat-1',
      identity: const SimpleLaunchIdentity(
        cli: CliTool.claude,
        expertKey: 'ex-key',
      ),
    );

    expect(plan.mode, SessionRuntimeMode.simple);
    expect(plan.workspaceId, 'ws-1');
    expect(plan.sessionId, 'sess-1');
    expect(plan.memberId, 'seat-1');
    expect(plan.expertKey, 'ex-key');
    expect(plan.teamId, isNull);
    expect(plan.runtimeBundle.skillIds, ['ex', 'ws']);
    expect(plan.member.id, 'ex');
  });

  test('simple plan uses builtin default when expertKey empty', () async {
    resolver.packs[kBuiltinDefaultExpertKey] = ExpertCapabilityPack(
      member: const TeamMemberConfig(id: 'default', name: 'Default'),
      bundle: const ConfigBundle(skillIds: ['def']),
    );
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['ws']);

    final plan = await builder.buildSimple(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      memberId: 'seat-1',
      identity: const SimpleLaunchIdentity(
        cli: CliTool.claude,
        expertKey: '  ',
      ),
    );

    expect(plan.expertKey, kBuiltinDefaultExpertKey);
    expect(plan.runtimeBundle.skillIds, ['def', 'ws']);
  });

  test('simple plan applies identity fields to expert pack member', () async {
    resolver.packs['ex-key'] = ExpertCapabilityPack(
      member: const TeamMemberConfig(
        id: 'ex',
        name: 'Expert',
        // Packs often omit cli; staging would otherwise fall back to Claude.
      ),
      bundle: const ConfigBundle(),
    );

    final plan = await builder.buildSimple(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      memberId: 'seat-1',
      identity: const SimpleLaunchIdentity(
        cli: CliTool.cursor,
        provider: 'cursor-account',
        model: 'gpt-5.5',
        effort: 'high',
        expertKey: 'ex-key',
        presetId: 'preset-1',
      ),
    );

    expect(plan.member.cli, CliTool.cursor);
    expect(plan.member.provider, 'cursor-account');
    expect(plan.member.model, 'gpt-5.5');
    expect(plan.member.effort, 'high');
    expect(plan.presetId, 'preset-1');
  });

  test('team plan merges team > expert > workspace per seat', () async {
    resolver.packs['e-key'] = ExpertCapabilityPack(
      member: const TeamMemberConfig(id: 'e', name: 'Expert'),
      bundle: const ConfigBundle(skillIds: ['e']),
    );
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['w']);

    const team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      skillIds: ['t'],
    );
    const slot = TeamRosterSlot(id: 'slot-1', expertKey: 'e-key');

    final plan = await builder.buildTeamSeat(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      team: team,
      slot: slot,
    );

    expect(plan.mode, SessionRuntimeMode.team);
    expect(plan.teamId, 'team-1');
    expect(plan.memberId, 'slot-1');
    expect(plan.expertKey, 'e-key');
    expect(plan.runtimeBundle.skillIds, ['t', 'e', 'w']);
    expect(plan.member.id, 'e');
  });

  test('synthesized slot without roster uses builtin default expertKey', () {
    const team = TeamProfile(id: 'team-1', name: 'Team');
    const member = TeamMemberConfig(
      id: 'team-lead',
      name: 'Lead',
      prompt: 'You are the lead',
    );

    final slot = teamRosterSlotForMember(team, member);

    expect(slot.id, 'team-lead');
    expect(slot.expertKey, isEmpty);
  });

  test('team seat with empty slot expertKey uses builtin default pack', () async {
    resolver.packs[kBuiltinDefaultExpertKey] = ExpertCapabilityPack(
      member: const TeamMemberConfig(id: 'default', name: 'Default'),
      bundle: const ConfigBundle(skillIds: ['def']),
    );
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['w']);

    const team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      skillIds: ['t'],
    );
    const member = TeamMemberConfig(
      id: 'team-lead',
      name: 'Lead',
      prompt: 'You are the lead',
    );
    final slot = teamRosterSlotForMember(team, member);

    final plan = await builder.buildTeamSeat(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      team: team,
      slot: slot,
      member: member,
    );

    expect(plan.expertKey, kBuiltinDefaultExpertKey);
    expect(plan.runtimeBundle.skillIds, ['t', 'def', 'w']);
    expect(plan.member.id, 'team-lead');
    expect(plan.member.prompt, 'You are the lead');
  });

  test('unknown expert key throws StateError', () async {
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['ws']);

    await expectLater(
      builder.buildSimple(
        workspaceId: 'ws-1',
        sessionId: 'sess-1',
        memberId: 'seat-1',
        identity: const SimpleLaunchIdentity(
          cli: CliTool.claude,
          expertKey: 'missing/expert',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('missing/expert'),
        ),
      ),
    );
  });
}

class _FakeExpertResolver extends ExpertCapabilityResolver {
  _FakeExpertResolver()
    : packs = {},
      super(
        installSkill: (_) async => null,
        installPlugin: (_) async => null,
        installMcp: (_) async => null,
      );

  final Map<String, ExpertCapabilityPack> packs;

  @override
  Future<ExpertCapabilityPack?> resolveKey(
    String expertKey, {void Function(String)? onDepProgress, 
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) async {
    return packs[expertKey];
  }
}
