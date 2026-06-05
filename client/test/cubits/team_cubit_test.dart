import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/team_cubit.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/plugin/team_plugin_linker_service.dart';
import 'package:teampilot/services/skill/team_skill_linker_service.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../support/post_frame_test_harness.dart';

Skill _skill(String id) => Skill(
  id: id,
  name: id,
  description: 'd',
  directory: id.contains(':') ? id.split(':').last : id,
  installedAt: 1,
  updatedAt: 1,
);

class _RecordingLinker extends TeamSkillLinkerService {
  _RecordingLinker()
    : super(appSkillsRoot: '/tmp', teamSkillsRootOverride: '/tmp/cli');

  final syncs =
      <({String teamId, List<String> skillIds, List<Skill> installed})>[];

  @override
  Future<TeamSkillSyncResult> syncForTeam({
    required String teamId,
    required List<String> skillIds,
    required List<Skill> installed,
  }) async {
    syncs.add((
      teamId: teamId,
      skillIds: List.of(skillIds),
      installed: List.of(installed),
    ));
    return const TeamSkillSyncResult();
  }
}

class _RecordingPluginLinker extends TeamPluginLinkerService {
  _RecordingPluginLinker()
    : super(appPluginsRoot: '/tmp');

  final syncs =
      <({String teamId, List<String> pluginIds, List<Plugin> installed})>[];

  @override
  Future<TeamPluginSyncResult> syncForTeam({
    required String teamId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async {
    syncs.add((
      teamId: teamId,
      pluginIds: List.of(pluginIds),
      installed: List.of(installed),
    ));
    return const TeamPluginSyncResult();
  }
}

class _RecordingLifecycleService extends SessionLifecycleService {
  _RecordingLifecycleService()
    : super(appDataBasePath: Directory.systemTemp.path);

  final destroyedTeams = <String>[];

  @override
  Future<void> destroyCliToolState(String teamId) async {
    destroyedTeams.add(teamId);
  }
}

TeamRepository _repo(Directory dir) =>
    TeamRepository(rootDir: p.join(dir.path, 'teams'));

Future<void> _deleteTempDirBestEffort(Directory dir) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (attempt == 7) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
    }
  }
}

/// [TeamCubit.addTeam] / [TeamCubit.deleteSelected] schedule skill/plugin sync
/// with [unawaited]; drain microtasks before [TeamCubit.close].
Future<void> _drainAndCloseTeamCubit(TeamCubit cubit) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  if (!cubit.isClosed) {
    await cubit.close();
  }
}

void main() {
  late Directory appDataRoot;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    appDataRoot = await Directory.systemTemp.createTemp('teampilot_app_data_');
    final paths = AppPaths(appDataRoot.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: appDataRoot.path,
      cwd: appDataRoot.path,
    );
  });

  tearDown(() async {
    RuntimeStorageContext.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    await _deleteTempDirBestEffort(appDataRoot);
  });

  test('selectTeam syncs skills for selected team', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingLinker();
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      skillLinker: linker,
      installedSkillsLoader: () async => [_skill('a:foo')],
    );

    const team = TeamConfig(
      id: 't',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      skillIds: ['a:foo'],
    );
    await repo.saveTeams([team]);
    await cubit.load();
    expect(cubit.state.teams.length, 1);

    linker.syncs.clear();
    await cubit.selectTeam('t');

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
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      skillLinker: linker,
      installedSkillsLoader: () async => [_skill('a:foo'), _skill('b:bar')],
    );

    const team = TeamConfig(
      id: 't',
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
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      skillLinker: linker,
      installedSkillsLoader: () async => [],
    );

    const team = TeamConfig(
      id: 't',
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

  test('removePluginFromAllTeams prunes all teams and syncs each', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingPluginLinker();
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: linker,
      installedPluginsLoader: () async => [],
    );

    const teamA = TeamConfig(
      id: 'a',
      name: 'A',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1'],
    );
    const teamB = TeamConfig(
      id: 'b',
      name: 'B',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1'],
    );
    await repo.saveTeams([teamA, teamB]);
    await cubit.load();
    await cubit.selectTeam('b');
    linker.syncs.clear();

    await cubit.removePluginFromAllTeams('acme/market/p1');

    expect(
      cubit.state.teams.every((t) => !t.pluginIds.contains('acme/market/p1')),
      isTrue,
    );
    expect(linker.syncs.map((s) => s.teamId).toSet(), {'a', 'b'});

    await dir.delete(recursive: true);
  });

  test('updateSelected syncs when pluginIds change', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingPluginLinker();
    const plugin = Plugin(
      id: 'acme/market/p1',
      name: 'p1',
      description: 'd',
      version: '1.0.0',
      directory: 'acme__market__p1',
      capabilities: PluginCapabilities(),
      installedAt: 1,
      updatedAt: 1,
    );
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: linker,
      installedPluginsLoader: () async => [plugin],
    );

    const team = TeamConfig(
      id: 't',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
    );
    await repo.saveTeams([team]);
    await cubit.load();
    linker.syncs.clear();

    await cubit.updateSelected(
      cubit.state.selectedTeam!.copyWith(pluginIds: ['acme/market/p1']),
    );

    expect(linker.syncs, isNotEmpty);
    expect(linker.syncs.last.pluginIds, ['acme/market/p1']);

    await dir.delete(recursive: true);
  });

  test('syncTeamsUsingPlugin syncs all teams referencing plugin id', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingPluginLinker();
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: linker,
      installedPluginsLoader: () async => [],
    );

    const teamA = TeamConfig(
      id: 'a',
      name: 'A',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1'],
    );
    const teamB = TeamConfig(
      id: 'b',
      name: 'B',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1', 'other/p2'],
    );
    await repo.saveTeams([teamA, teamB]);
    await cubit.load();
    linker.syncs.clear();

    await cubit.syncTeamsUsingPlugin('acme/market/p1');

    expect(linker.syncs.map((s) => s.teamId).toSet(), {'a', 'b'});
    await dir.delete(recursive: true);
  });

  test('addTeam requires non-empty unique name', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );
    await cubit.load();

    expect(await cubit.addTeam(''), isFalse);
    expect(await cubit.addTeam('Alpha'), isTrue);
    expect(cubit.state.selectedTeam?.id, 'alpha');
    expect(cubit.state.selectedTeam?.name, 'Alpha');
    expect(
      cubit.state.selectedTeam?.members.map((m) => m.id).toList(),
      ['team-lead', 'developer', 'reviewer'],
    );
    expect(
      cubit.state.selectedTeam?.members.every((m) => m.prompt.trim().isNotEmpty),
      isTrue,
    );
    expect(await cubit.addTeam('Alpha'), isFalse);

    await _drainAndCloseTeamCubit(cubit);
    await dir.delete(recursive: true);
  });

  test('deleteMember cannot remove team-lead', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final cubit = TeamCubit(
      repository: _repo(dir),
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );
    await cubit.load();

    expect(await cubit.addTeam('Alpha'), isTrue);
    final lead = cubit.state.selectedTeam!.members.firstWhere(
      TeamMemberNaming.isTeamLead,
    );
    await cubit.deleteMember(lead.id);
    expect(cubit.state.selectedTeam?.members.length, 3);
    expect(cubit.state.statusMessage, contains('team-lead'));

    await _drainAndCloseTeamCubit(cubit);
    await dir.delete(recursive: true);
  });

  test(
    'renameSelectedTeamName updates storage and removes old files',
    () async {
      final dir = await Directory.systemTemp.createTemp('team-cubit-');
      final lifecycle = _RecordingLifecycleService();
      final repo = TeamRepository(
        rootDir: p.join(dir.path, 'teams'),
        lifecycleService: lifecycle,
      );
      final cubit = TeamCubit(
        repository: repo,
        sessionRepository: SessionRepository(),
        reloadProjects: () async {},
        executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      );
      const team = TeamConfig(
        id: 'old',
        name: 'Old',
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await repo.saveTeams([team]);
      await cubit.load();

      expect(await cubit.renameSelectedTeamName('New'), isTrue);
      expect(cubit.state.selectedTeam?.name, 'New');
      expect(File(p.join(dir.path, 'teams', 'New.json')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'teams', 'Old.json')).existsSync(), isFalse);
      expect(lifecycle.destroyedTeams, isEmpty);

      await cubit.deleteSelected();
      expect(lifecycle.destroyedTeams, ['old']);
      expect(File(p.join(dir.path, 'teams', 'New.json')).existsSync(), isFalse);

      await _drainAndCloseTeamCubit(cubit);
      await dir.delete(recursive: true);
    },
  );

  test('load seeds default project when creating Default Team', () async {
    final base = await Directory.systemTemp.createTemp('team_default_project_');
    final sessionRepo = SessionRepository();
    var reloadCount = 0;
    final cubit = TeamCubit(
      repository: _repo(base),
      sessionRepository: sessionRepo,
      reloadProjects: () async => reloadCount++,
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );

    await cubit.load();

    final team = cubit.state.teams.single;
    expect(team.name, 'Default Team');
    expect(reloadCount, 1);
    final projects = await sessionRepo.loadProjects();
    expect(projects.where((p) => p.teamId == team.id), hasLength(1));
    expect(
      projects.singleWhere((p) => p.teamId == team.id).display,
      'Default Team',
    );

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('addTeam creates team runtime profile directories', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_');
    final cubit = TeamCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      skillLinker: _RecordingLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(await cubit.addTeam('alpha'), isTrue);

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'alpha');
    expect(await Directory(teamRoot).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isFalse);
    expect(cubit.state.teams.single.cli, CliTool.flashskyai);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('addTeam accepts codex now that it is launch-supported', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_cli_');
    final cubit = TeamCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(await cubit.addTeam('beta', cli: CliTool.codex), isTrue);
    expect(cubit.state.teams.single.cli, CliTool.codex);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('previewFor resolves executable from team cli when available', () async {
    final base = await Directory.systemTemp.createTemp('team_cli_preview_');
    final cubit = TeamCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      cliExecutableResolver: (cli) =>
          cli == CliTool.claude ? '/opt/bin/claude' : cli.value,
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );
    const member = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
    const team = TeamConfig(
      id: 'claude-team',
      name: 'Claude Team',
      cli: CliTool.claude,
      members: [member],
    );
    await _repo(base).saveTeams([team]);
    await cubit.load(awaitProfiles: true);

    expect(cubit.previewFor(member), startsWith('/opt/bin/claude '));

    await _drainAndCloseTeamCubit(cubit);
    await drainPendingAsyncWork();
    await deleteTempDirBestEffort(base);
  });

  test('updateMember only saves Claude member metadata', () async {
    final base = await Directory.systemTemp.createTemp(
      'team_claude_member_metadata_',
    );
    final repo = _repo(base);
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'claude',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    const member = TeamMemberConfig(
      id: 'developer',
      name: 'developer',
      provider: 'deepseek',
      model: 'deepseek-chat',
    );
    const team = TeamConfig(
      id: 'claude-team',
      name: 'Claude Team',
      cli: CliTool.claude,
      members: [member],
    );
    await repo.saveTeams([team]);
    await cubit.load();

    await cubit.updateMember(
      'developer',
      member.copyWith(provider: 'moonshot', model: 'kimi-k2'),
    );

    final settingsFile = File(
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'Claude Team',
        configProfileAdhocSessionId,
        'claude',
        'settings',
        'developer.json',
      ),
    );
    expect(await settingsFile.exists(), isFalse);
    final dev = cubit.state.selectedTeam!.members.firstWhere(
      (m) => m.id == 'developer',
    );
    expect(dev.provider, 'moonshot');
    expect(dev.model, 'kimi-k2');
    expect(
      cubit.state.selectedTeam!.members.any(
        (m) => m.id == 'team-lead',
      ),
      isTrue,
    );

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('launchSelectedTeam writes Claude roster under CLI team name', () async {
    final base = await Directory.systemTemp.createTemp(
      'team_claude_direct_launch_',
    );
    final repo = _repo(base);
    final launched = <String>[];
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'claude',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
      launcher: (_, member) async => launched.add(member.name),
    );

    const team = TeamConfig(
      id: 'claude-team',
      name: 'Claude Team',
      cli: CliTool.claude,
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'developer', name: 'developer'),
      ],
    );
    await repo.saveTeams([team]);
    await cubit.load();

    await cubit.launchSelectedTeam();

    expect(launched, ['team-lead', 'developer']);
    final memberRoot = Directory(
      p.join(base.path, 'config-profiles', 'teams', 'claude-team', 'members'),
    );
    final memberDirs = await memberRoot
        .list()
        .where((entry) => entry is Directory)
        .map((entry) => p.basename(entry.path))
        .toList();
    expect(memberDirs, ['claude-team']);

    final rosterFile = File(
      p.join(
        memberRoot.path,
        'claude-team',
        'claude',
        'teams',
        'claude-team',
        'config.json',
      ),
    );
    expect(await rosterFile.exists(), isTrue);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('load creates runtime profile directories for default team', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_load_');
    final cubit = TeamCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    await cubit.load(awaitProfiles: true);

    final teamRoot = p.join(
      base.path,
      'config-profiles',
      'teams',
      'default-team',
    );
    expect(await Directory(teamRoot).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isFalse);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('bindClaudeProviderForTeamsWithoutBinding sets claude team provider', () async {
    final dir = await Directory.systemTemp.createTemp('team-bind-provider-');
    final repo = _repo(dir);
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'claude',
      pluginLinker: _RecordingPluginLinker(),
    );

    const team = TeamConfig(
      id: 'default-team',
      name: 'Default Team',
      cli: CliTool.claude,
      members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
    );
    await repo.saveTeams([team]);
    await cubit.load();

    await cubit.bindClaudeProviderForTeamsWithoutBinding('deepseek');

    expect(
      cubit.state.selectedTeam!.providerIdsByTool['claude'],
      'deepseek',
    );
    final reloaded = await repo.loadTeams();
    expect(reloaded.single.providerIdsByTool['claude'], 'deepseek');

    await _drainAndCloseTeamCubit(cubit);
    await dir.delete(recursive: true);
  });

  test('bindClaudeProviderForTeamsWithoutBinding keeps existing binding', () async {
    final dir = await Directory.systemTemp.createTemp('team-bind-existing-');
    final repo = _repo(dir);
    final cubit = TeamCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadProjects: () async {},
      executableResolver: () => 'claude',
      pluginLinker: _RecordingPluginLinker(),
    );

    const team = TeamConfig(
      id: 'default-team',
      name: 'Default Team',
      cli: CliTool.claude,
      members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      providerIdsByTool: {'claude': 'official'},
    );
    await repo.saveTeams([team]);
    await cubit.load();

    await cubit.bindClaudeProviderForTeamsWithoutBinding('deepseek');

    expect(
      cubit.state.selectedTeam!.providerIdsByTool['claude'],
      'official',
    );

    await _drainAndCloseTeamCubit(cubit);
    await dir.delete(recursive: true);
  });
}
