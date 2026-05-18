import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/team_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/config_profile_service.dart';
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

  test('addTeam requires non-empty unique name', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final cubit = TeamCubit(
      repository: repo,
      executableResolver: () => 'flashskyai',
    );
    await cubit.load();

    expect(await cubit.addTeam(''), isFalse);
    expect(await cubit.addTeam('Alpha'), isTrue);
    expect(cubit.state.selectedTeam?.name, 'Alpha');
    expect(await cubit.addTeam('Alpha'), isFalse);

    await dir.delete(recursive: true);
  });

  test(
    'renameSelectedTeamName updates storage and removes old files',
    () async {
      final dir = await Directory.systemTemp.createTemp('team-cubit-');
      final repo = _repo(dir);
      final cubit = TeamCubit(
        repository: repo,
        executableResolver: () => 'flashskyai',
      );
      const team = TeamConfig(
        id: 'Old',
        name: 'Old',
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await repo.saveTeams([team]);
      await cubit.load();

      expect(await cubit.renameSelectedTeamName('New'), isTrue);
      expect(cubit.state.selectedTeam?.name, 'New');
      expect(File(p.join(dir.path, 'teams', 'New.json')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'teams', 'Old.json')).existsSync(), isFalse);

      await dir.delete(recursive: true);
    },
  );

  test('addTeam creates team runtime profile directories', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_');
    final cubit = TeamCubit(
      repository: _repo(base),
      executableResolver: () => 'flashskyai',
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(await cubit.addTeam('alpha'), isTrue);

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'alpha');
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'codex')).exists(), isFalse);
    expect(await Directory(p.join(teamRoot, 'claude')).exists(), isFalse);
    expect(cubit.state.teams.single.cli, TeamCli.flashskyai);

    await cubit.close();
    await base.delete(recursive: true);
  });

  test('addTeam rejects unsupported cli backends', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_cli_');
    final cubit = TeamCubit(
      repository: _repo(base),
      executableResolver: () => 'flashskyai',
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(await cubit.addTeam('beta', cli: TeamCli.codex), isFalse);
    expect(cubit.state.teams, isEmpty);

    await cubit.close();
    await base.delete(recursive: true);
  });

  test('load creates runtime profile directories for default team', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_load_');
    final cubit = TeamCubit(
      repository: _repo(base),
      executableResolver: () => 'flashskyai',
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    await cubit.load();

    final teamRoot = p.join(
      base.path,
      'config-profiles',
      'teams',
      'Default Team',
    );
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'codex')).exists(), isFalse);
    expect(await Directory(p.join(teamRoot, 'claude')).exists(), isFalse);

    await cubit.close();
    await base.delete(recursive: true);
  });
}
