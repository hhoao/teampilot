import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';

import '../support/post_frame_test_harness.dart';

const _leadSlot = TeamRosterSlot(
  id: 'team-lead',
  expertKey: 'teampilot/builtin/team-lead',
);

const _registrySlot = TeamRosterSlot(
  id: 'team-lead',
  expertKey: 'hhoao/teampilot/member-hub/gstack-office-hours',
);

const _registryExpert = DiscoverableMember(
  key: 'hhoao/teampilot/member-hub/gstack-office-hours',
  name: 'Office Hours',
  description: '',
  category: 'Workflow',
  source: ExpertMemberSource.registry,
  member: DiscoverableTeamMember(name: 'office-hours'),
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  LaunchProfileCubit build(
    LaunchProfileRepository repo, {
    CompositeExpertHubSource? expertHubSource,
  }) => LaunchProfileCubit(
    repository: repo,
    sessionRepository: SessionRepository(),
    executableResolver: () => 'flashskyai',
    expertHubSource: expertHubSource,
  );

  test(
    'addClonedTeam persists ids, roster, and selects the new team',
    () async {
      final dir = await Directory.systemTemp.createTemp('clone-team-');
      final repo = testLaunchProfileRepository(dir);
      final cubit = build(repo);
      await cubit.load();

      final id = await cubit.addClonedTeam(
        name: 'Research Squad',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        roster: const [_leadSlot],
        skillIds: const ['anthropics/skills:deep-research'],
        pluginIds: const ['acme/plugins/linter'],
        mcpServerIds: const ['context7'],
        description: 'deep research',
        extraArgs: '--foo',
      );

      expect(id, isNotNull);
      final team = cubit.state.teams.firstWhere((t) => t.id == id);
      expect(team.name, 'Research Squad');
      expect(team.cli, CliTool.claude);
      expect(team.skillIds, ['anthropics/skills:deep-research']);
      expect(team.pluginIds, ['acme/plugins/linter']);
      expect(team.mcpServerIds, ['context7']);
      expect(cubit.state.selectedTeamId, id);

      final reloaded = await repo.loadTeamProfiles();
      expect(reloaded.any((t) => t.id == id), isTrue);

      await dir.delete(recursive: true);
    },
  );

  test('addClonedTeam auto-renames on display-name collision', () async {
    final dir = await Directory.systemTemp.createTemp('clone-team-2-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = build(repo);
    await cubit.load();

    final first = await cubit.addClonedTeam(
      name: 'Squad',
      cli: CliTool.claude,
      roster: const [_leadSlot],
    );
    final second = await cubit.addClonedTeam(
      name: 'Squad',
      cli: CliTool.claude,
      roster: const [_leadSlot],
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first, isNot(second));
    final names = cubit.state.teams.map((t) => t.name).toList();
    expect(names.contains('Squad'), isTrue);
    expect(names.where((n) => n.startsWith('Squad')).length, 2);

    await dir.delete(recursive: true);
  });

  test(
    'addClonedTeam materializes registry roster when expert hub source is wired',
    () async {
      final dir = await Directory.systemTemp.createTemp('clone-team-hub-');
      final repo = testLaunchProfileRepository(dir);
      final cubit = build(
        repo,
        expertHubSource: CompositeExpertHubSource(
          builtIns: const [],
          registry: _StaticRegistry(const [_registryExpert]),
        ),
      );
      await cubit.load();

      final id = await cubit.addClonedTeam(
        name: 'gstack Requirement Dev',
        cli: CliTool.claude,
        roster: const [_registrySlot],
      );

      expect(id, isNotNull);
      final team = cubit.state.teams.firstWhere((t) => t.id == id);
      expect(team.roster, hasLength(1));
      expect(team.members, hasLength(1));
      expect(team.members.single.id, 'team-lead');
      expect(team.members.single.name, 'Office Hours');

      await dir.delete(recursive: true);
    },
  );
}

class _StaticRegistry implements ExpertHubSource {
  _StaticRegistry(this.members);

  final List<DiscoverableMember> members;

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => members;

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async =>
      const [];
}
