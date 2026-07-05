import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/expert_hub/member_clone_service.dart';

import '../../support/post_frame_test_harness.dart';

DiscoverableMember member({List<SkillDependencyRef> skillDeps = const []}) =>
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

  test('addToTeam installs skill deps and adds member to team', () async {
    final dir = await Directory.systemTemp.createTemp('member-clone-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;

    final service = MemberCloneService(
      installSkill: (d) async => 'anthropics/skills:${d.directory.split('/').last}',
    );

    final result = await service.addToTeam(
      teamId: teamId,
      member: member(
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

    final team = cubit.state.teams.firstWhere((t) => t.id == teamId);
    expect(team.members.any((m) => m.id == result.memberId), isTrue);
    final added = team.members.firstWhere((m) => m.id == result.memberId);
    expect(added.name, 'Developer (2)');
    expect(added.prompt, 'You implement code.');

    await cubit.close();
    await dir.delete(recursive: true);
  });

  test('a failed skill dep is non-blocking; member still added', () async {
    final dir = await Directory.systemTemp.createTemp('member-clone-fail-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;
    final beforeCount = cubit.state.teams.first.members.length;

    final service = MemberCloneService(installSkill: (d) async => null);

    final result = await service.addToTeam(
      teamId: teamId,
      member: member(
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
    expect(
      cubit.state.teams.first.members.length,
      beforeCount + 1,
    );

    await cubit.close();
    await dir.delete(recursive: true);
  });

  test('throws MemberAddException when team id is unknown', () async {
    final dir = await Directory.systemTemp.createTemp('member-clone-missing-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();

    final service = MemberCloneService(installSkill: (d) async => 'skill-id');

    expect(
      () => service.addToTeam(
        teamId: 'missing-team',
        member: member(),
        launchProfiles: cubit,
      ),
      throwsA(isA<MemberAddException>()),
    );

    await cubit.close();
    await dir.delete(recursive: true);
  });

  test('addMemberToTeam persists member to repository', () async {
    final dir = await Directory.systemTemp.createTemp('member-add-team-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;

    final added = await cubit.addMemberToTeam(
      teamId,
      const TeamMemberConfig(
        id: 'developer',
        name: 'Developer',
        prompt: 'Build things.',
        joinedAt: 0,
      ),
    );

    expect(added, isNotNull);
    expect(added!.id, 'developer-2');
    expect(added.prompt, 'Build things.');

    final reloaded = await repo.loadTeamProfiles();
    final team = reloaded.firstWhere((t) => t.id == teamId);
    expect(team.members.any((m) => m.id == 'developer-2'), isTrue);

    await cubit.close();
    await dir.delete(recursive: true);
  });
}
