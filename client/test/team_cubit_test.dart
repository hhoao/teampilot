import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/team_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/team_skill_linker_service.dart';

Skill _skill(String id) => Skill(
      id: id,
      name: id,
      description: 'd',
      directory: id.contains(':') ? id.split(':').last : id,
      installedAt: 1,
      updatedAt: 1,
    );

class _RecordingLinker extends TeamSkillLinkerService {
  _RecordingLinker() : super(appSkillsRoot: '/tmp', cliSkillsDir: '/tmp/cli');

  final syncs = <({List<String> skillIds, List<Skill> installed})>[];

  @override
  Future<TeamSkillSyncResult> syncForTeam({
    required List<String> skillIds,
    required List<Skill> installed,
  }) async {
    syncs.add((skillIds: List.of(skillIds), installed: List.of(installed)));
    return const TeamSkillSyncResult();
  }
}

TeamRepository _repo(Directory dir) => TeamRepository(
      rootDir: p.join(dir.path, 'teams'),
      cliTeamsDir: p.join(dir.path, 'cli-teams'),
    );

void main() {
  test('selectTeam syncs skills for selected team', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingLinker();
    final cubit = TeamCubit(
      repository: repo,
      executableResolver: () => 'flashskyai',
      skillLinker: linker,
      installedSkillsLoader: () async => [_skill('a:foo')],
    );

    const team = TeamConfig(
      id: 'T',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      skillIds: ['a:foo'],
    );
    await repo.saveTeams([team]);
    await cubit.load();
    expect(cubit.state.teams.length, 1);

    linker.syncs.clear();
    await cubit.selectTeam('T');

    expect(linker.syncs, hasLength(1));
    expect(linker.syncs.single.skillIds, ['a:foo']);

    await dir.delete(recursive: true);
  });

  test('updateSelected syncs when skillIds change', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingLinker();
    final cubit = TeamCubit(
      repository: repo,
      executableResolver: () => 'flashskyai',
      skillLinker: linker,
      installedSkillsLoader: () async => [_skill('a:foo'), _skill('b:bar')],
    );

    const team = TeamConfig(
      id: 'T',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
    );
    await repo.saveTeams([team]);
    await cubit.load();
    linker.syncs.clear();

    await cubit.updateSelected(
      cubit.state.selectedTeam!.copyWith(skillIds: ['a:foo', 'b:bar']),
    );

    expect(linker.syncs, isNotEmpty);
    expect(linker.syncs.last.skillIds, ['a:foo', 'b:bar']);

    await dir.delete(recursive: true);
  });

  test('removeSkillFromAllTeams prunes and syncs', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingLinker();
    final cubit = TeamCubit(
      repository: repo,
      executableResolver: () => 'flashskyai',
      skillLinker: linker,
      installedSkillsLoader: () async => [],
    );

    const team = TeamConfig(
      id: 'T',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      skillIds: ['gone'],
    );
    await repo.saveTeams([team]);
    await cubit.load();
    expect(cubit.state.teams.single.skillIds, ['gone']);
    linker.syncs.clear();

    await cubit.removeSkillFromAllTeams('gone');

    expect(cubit.state.selectedTeam?.skillIds, isEmpty);
    expect(linker.syncs, isNotEmpty);

    await dir.delete(recursive: true);
  });
}
