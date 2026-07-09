import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';

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

  test('addExpertToTeam installs skill deps and adds roster slot', () async {
    final dir = await Directory.systemTemp.createTemp('member-roster-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = buildCubit(repo);
    await cubit.load();
    final teamId = cubit.state.teams.first.id;

    final service = MemberRosterService(
      installSkill: (d) async => 'anthropics/skills:${d.directory.split('/').last}',
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

    final service = MemberRosterService(installSkill: (d) async => null);

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

    final service = MemberRosterService(installSkill: (d) async => 'skill-id');

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
