import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/stub_member_roster_service.dart';

const _pluginDep = PluginDependencyRef(
  marketplaceOwner: 'o',
  marketplaceName: 'n',
  marketplaceBranch: 'main',
  entryName: 'plug',
  name: 'Plug',
);

const _mcpDep = McpDependencyRef(
  id: 'context7',
  name: 'Context7',
  server: {'command': 'npx'},
);

DiscoverableMember member({
  List<SkillDependencyRef> skillDeps = const [],
  List<PluginDependencyRef> pluginDeps = const [],
  List<McpDependencyRef> mcpDeps = const [],
}) =>
    DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Developer',
      description: 'Implements features',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: const DiscoverableTeamMember(
        name: 'developer',
        prompt: 'You implement code.',
      ),
      skillDeps: skillDeps,
      pluginDeps: pluginDeps,
      mcpDeps: mcpDeps,
    );

MemberRosterService buildService({
  SkillDepInstaller? installSkill,
  PluginDepInstaller? installPlugin,
  McpDepInstaller? installMcp,
}) => stubMemberRosterService(
  installSkill: installSkill,
  installPlugin: installPlugin,
  installMcp: installMcp,
);

LaunchProfileCubit buildCubit(LaunchProfileRepository repo) =>
    LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      executableResolver: () => 'flashskyai',
    );

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('addExpertToTeam installs skill deps and adds roster slot', () async {
    final dir = await Directory.systemTemp.createTemp('member-roster-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;

    final service = buildService(
      installSkill: (d) async =>
          'anthropics/skills:${d.directory.split('/').last}',
    );

    final result = await service.addExpertToTeam(
      teamId: teamId,
      expert: member(
        skillDeps: const [
          SkillDependencyRef(
            repoOwner: 'anthropics',
            repoName: 'skills',
            repoBranch: 'main',
            directory: 'skills/deep-research',
            name: 'deep-research',
          ),
        ],
      ),
      launchProfiles: cubit,
    );

    expect(result.failedDeps, isEmpty);
    expect(result.installedSkillIds, ['anthropics/skills:deep-research']);
    expect(result.memberId, isNotEmpty);
    expect(result.expertKey, 'teampilot/builtin/developer');

    final team = cubit.state.teams.firstWhere((t) => t.id == teamId);
    expect(team.roster.any((s) => s.id == result.memberId), isTrue);
    expect(
      team.roster.firstWhere((s) => s.id == result.memberId).expertKey,
      'teampilot/builtin/developer',
    );
    expect(team.members.any((m) => m.id == result.memberId), isTrue);
    expect(
      team.members.firstWhere((m) => m.id == result.memberId).prompt,
      contains('Implement'),
    );

    await cubit.close();
    await dir.delete(recursive: true);
  });

  test('a failed skill dep is non-blocking; roster slot still added', () async {
    final dir = await Directory.systemTemp.createTemp('member-roster-fail-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;
    final beforeCount = cubit.state.teams.first.roster.length;

    final service = buildService(installSkill: (d) async => null);

    final result = await service.addExpertToTeam(
      teamId: teamId,
      expert: member(
        skillDeps: const [
          SkillDependencyRef(
            repoOwner: 'anthropics',
            repoName: 'skills',
            repoBranch: 'main',
            directory: 'skills/deep-research',
            name: 'deep-research',
          ),
        ],
      ),
      launchProfiles: cubit,
    );

    expect(result.installedSkillIds, isEmpty);
    expect(result.failedDeps, hasLength(1));
    expect(result.failedDeps.single.name, 'deep-research');
    expect(result.memberId, isNotEmpty);
    expect(cubit.state.teams.first.roster.length, beforeCount + 1);

    await cubit.close();
    await dir.delete(recursive: true);
  });

  test('throws MemberAddException when team id is unknown', () async {
    final dir = await Directory.systemTemp.createTemp('member-roster-missing-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();

    final service = buildService(installSkill: (d) async => 'skill-id');

    expect(
      () => service.addExpertToTeam(
        teamId: 'missing-team',
        expert: member(),
        launchProfiles: cubit,
      ),
      throwsA(isA<MemberAddException>()),
    );

    await cubit.close();
    await dir.delete(recursive: true);
  });

  test(
    'addExpertToTeam installs plugin/mcp deps without mutating team bundle',
    () async {
      final dir = await Directory.systemTemp.createTemp('member-roster-pack-');
      final repo = testLaunchProfileRepository(dir);
      final cubit = buildCubit(repo);
      await cubit.load();
      final teamId = cubit.state.teams.first.id;
      final before = cubit.state.teams.firstWhere((t) => t.id == teamId);
      final beforeSkillIds = List<String>.from(before.skillIds);
      final beforePluginIds = List<String>.from(before.pluginIds);
      final beforeMcpIds = List<String>.from(before.mcpServerIds);

      var pluginCalled = false;
      var mcpCalled = false;
      final service = buildService(
        installPlugin: (dep) async {
          pluginCalled = true;
          expect(dep, _pluginDep);
          return 'o/n/plug';
        },
        installMcp: (dep) async {
          mcpCalled = true;
          expect(dep, _mcpDep);
          return 'context7';
        },
      );

      final result = await service.addExpertToTeam(
        teamId: teamId,
        expert: member(pluginDeps: const [_pluginDep], mcpDeps: const [_mcpDep]),
        launchProfiles: cubit,
      );

      expect(pluginCalled, isTrue);
      expect(mcpCalled, isTrue);
      expect(result.installedSkillIds, isEmpty);
      expect(result.installedPluginIds, ['o/n/plug']);
      expect(result.installedMcpServerIds, ['context7']);
      expect(result.failedDeps, isEmpty);
      expect(result.memberId, isNotEmpty);

      final after = cubit.state.teams.firstWhere((t) => t.id == teamId);
      expect(after.skillIds, beforeSkillIds);
      expect(after.pluginIds, beforePluginIds);
      expect(after.mcpServerIds, beforeMcpIds);

      await cubit.close();
      await dir.delete(recursive: true);
    },
  );

  test('addExpertToTeam persists roster slot to repository', () async {
    final dir = await Directory.systemTemp.createTemp('member-add-team-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;

    final added = await cubit.addExpertToTeam(
      teamId,
      'teampilot/builtin/developer',
      slotIdHint: 'developer',
    );

    expect(added, isNotNull);
    expect(added!.id, 'developer-2');
    expect(added.expertKey, 'teampilot/builtin/developer');

    final reloaded = await repo.loadTeamProfiles();
    final team = reloaded.firstWhere((t) => t.id == teamId);
    expect(team.roster.any((s) => s.id == 'developer-2'), isTrue);

    await cubit.close();
    await dir.delete(recursive: true);
  });
}
