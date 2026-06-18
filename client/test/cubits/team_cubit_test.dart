import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/plugin/profile_plugin_linker_service.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../support/post_frame_test_harness.dart';

class _RecordingPluginLinker extends ProfilePluginLinkerService {
  _RecordingPluginLinker() : super(appPluginsRoot: '/tmp');

  final syncs =
      <({String profileId, List<String> pluginIds, List<Plugin> installed})>[];

  @override
  Future<ProfilePluginSyncResult> syncForProfile({
    required String profileId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async {
    syncs.add((
      profileId: profileId,
      pluginIds: List.of(pluginIds),
      installed: List.of(installed),
    ));
    return const ProfilePluginSyncResult();
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

LaunchProfileRepository _repo(Directory dir) =>
    LaunchProfileRepository(rootDir: p.join(dir.path, 'launch-profiles'));

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

/// [LaunchProfileCubit.addTeam] / [LaunchProfileCubit.deleteSelected] schedule skill/plugin sync
/// with [unawaited]; drain microtasks before [LaunchProfileCubit.close].
Future<void> _drainAndCloseTeamCubit(LaunchProfileCubit cubit) async {
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
    await drainPendingAsyncWork();
    RuntimeStorageContext.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    await _deleteTempDirBestEffort(appDataRoot);
  });

  test('removeSkillFromAllTeams prunes skillIds without linker sync', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );

    const team = TeamProfile(
      id: 't',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      skillIds: ['gone'],
    );
    await repo.saveTeamProfiles([team]);
    await cubit.load();
    expect(cubit.state.teams.single.skillIds, ['gone']);

    await cubit.removeSkillFromAllTeams('gone');

    expect(cubit.state.selectedTeam?.skillIds, isEmpty);
    final persisted = await repo.loadTeamProfiles();
    expect(persisted.single.skillIds, isEmpty);

    await dir.delete(recursive: true);
  });

  test('removePluginFromAllTeams prunes all teams and syncs each', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final linker = _RecordingPluginLinker();
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: linker,
      installedPluginsLoader: () async => [],
    );

    const teamA = TeamProfile(
      id: 'a',
      name: 'A',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1'],
    );
    const teamB = TeamProfile(
      id: 'b',
      name: 'B',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1'],
    );
    await repo.saveTeamProfiles([teamA, teamB]);
    await cubit.load();
    await cubit.selectTeam('b');
    linker.syncs.clear();

    await cubit.removePluginFromAllTeams('acme/market/p1');

    expect(
      cubit.state.teams.every((t) => !t.pluginIds.contains('acme/market/p1')),
      isTrue,
    );
    expect(linker.syncs.map((s) => s.profileId).toSet(), {'a', 'b'});

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
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: linker,
      installedPluginsLoader: () async => [plugin],
    );

    const team = TeamProfile(
      id: 't',
      name: 'T',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
    );
    await repo.saveTeamProfiles([team]);
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
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: linker,
      installedPluginsLoader: () async => [],
    );

    const teamA = TeamProfile(
      id: 'a',
      name: 'A',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1'],
    );
    const teamB = TeamProfile(
      id: 'b',
      name: 'B',
      members: [TeamMemberConfig(id: 'm', name: 'm')],
      pluginIds: ['acme/market/p1', 'other/p2'],
    );
    await repo.saveTeamProfiles([teamA, teamB]);
    await cubit.load();
    linker.syncs.clear();

    await cubit.syncTeamsUsingPlugin('acme/market/p1');

    expect(linker.syncs.map((s) => s.profileId).toSet(), {'a', 'b'});
    await dir.delete(recursive: true);
  });

  test('addTeam requires non-empty unique name', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final repo = _repo(dir);
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );
    await cubit.load();

    expect(await cubit.addTeam(''), isFalse);
    expect(await cubit.addTeam('Alpha'), isTrue);
    expect(cubit.state.selectedTeam?.id, 'alpha');
    expect(cubit.state.selectedTeam?.name, 'Alpha');
    expect(cubit.state.selectedTeam?.members.map((m) => m.id).toList(), [
      'team-lead',
      'developer',
      'reviewer',
    ]);
    expect(
      cubit.state.selectedTeam?.members.every(
        (m) => m.prompt.trim().isNotEmpty,
      ),
      isTrue,
    );
    expect(await cubit.addTeam('Alpha'), isFalse);

    await _drainAndCloseTeamCubit(cubit);
    await dir.delete(recursive: true);
  });

  test('deleteMember cannot remove team-lead', () async {
    final dir = await Directory.systemTemp.createTemp('team-cubit-');
    final cubit = LaunchProfileCubit(
      repository: _repo(dir),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
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
      final repo = LaunchProfileRepository(
        rootDir: p.join(dir.path, 'launch-profiles'),
        lifecycleService: lifecycle,
      );
      final cubit = LaunchProfileCubit(
        repository: repo,
        sessionRepository: SessionRepository(),
        reloadWorkspaces: () async {},
        executableResolver: () => 'flashskyai',
        pluginLinker: _RecordingPluginLinker(),
      );
      const team = TeamProfile(
        id: 'old',
        name: 'Old',
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await repo.saveTeamProfiles([team]);
      await cubit.load();

      expect(await cubit.renameSelectedTeamName('New'), isTrue);
      expect(cubit.state.selectedTeam?.name, 'New');
      final identityFile = p.join(dir.path, 'launch-profiles', 'old', 'profile.json');
      expect(File(identityFile).existsSync(), isTrue);
      expect(File(identityFile).readAsStringSync(), contains('"name": "New"'));
      expect(lifecycle.destroyedTeams, isEmpty);

      await cubit.deleteSelected();
      expect(lifecycle.destroyedTeams, ['old']);
      expect(Directory(p.join(dir.path, 'launch-profiles', 'old')).existsSync(), isFalse);

      await _drainAndCloseTeamCubit(cubit);
      await dir.delete(recursive: true);
    },
  );

  test('load seeds default workspace when creating Default Team', () async {
    final base = await Directory.systemTemp.createTemp('team_default_workspace_');
    final sessionRepo = SessionRepository();
    var reloadCount = 0;
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: sessionRepo,
      reloadWorkspaces: () async => reloadCount++,
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );

    await cubit.load();

    final team = cubit.state.teams.single;
    expect(team.name, 'Default Team');
    expect(reloadCount, 1);
    final workspaces = await sessionRepo.loadWorkspaces();
    expect(workspaces, hasLength(1));
    expect(workspaces.single.display, 'Default Team');
    final sessions = await sessionRepo.loadSessions();
    expect(sessions.where((s) => s.sessionTeam == team.id), hasLength(1));

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('addTeam creates team runtime profile directories', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_');
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(await cubit.addTeam('alpha'), isTrue);

    final teamRoot = p.join(base.path, 'identities-runtime', 'alpha');
    expect(await Directory(teamRoot).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isFalse);
    expect(cubit.state.teams.single.cli, CliTool.claude);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('addTeam rejects codex in native team mode', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_cli_');
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(await cubit.addTeam('beta', cli: CliTool.codex), isFalse);
    expect(cubit.state.teams, isEmpty);
    expect(
      cubit.state.statusMessage,
      'CLI "codex" does not support native team mode.',
    );

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('addTeam accepts codex in mixed team mode', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_cli_');
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(
      await cubit.addTeam('beta', cli: CliTool.codex, teamMode: TeamMode.mixed),
      isTrue,
    );
    expect(cubit.state.teams.single.cli, CliTool.codex);
    expect(cubit.state.teams.single.teamMode, TeamMode.mixed);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('setMemberActivePreset syncs member cli from preset in mixed mode', () async {
    final base = await Directory.systemTemp.createTemp('team_member_preset_');
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    expect(
      await cubit.addTeam('mixed', cli: CliTool.claude, teamMode: TeamMode.mixed),
      isTrue,
    );
    final memberId = cubit.state.selectedTeam!.members.first.id;

    await cubit.setMemberActivePreset(
      memberId,
      'preset-codex',
      syncCli: CliTool.codex,
    );

    final member = cubit.state.selectedTeam!.members.firstWhere(
      (m) => m.id == memberId,
    );
    expect(member.activePresetId, 'preset-codex');
    expect(member.cli, CliTool.codex);

    await cubit.setMemberActivePreset(memberId, TeamProfile.inheritPresetId);

    final inherited = cubit.state.selectedTeam!.members.firstWhere(
      (m) => m.id == memberId,
    );
    expect(inherited.activePresetId, TeamProfile.inheritPresetId);
    expect(inherited.cli, CliTool.codex);

    await _drainAndCloseTeamCubit(cubit);
    await deleteTempDirBestEffort(base);
  });

  test('previewFor resolves executable from team cli when available', () async {
    final base = await Directory.systemTemp.createTemp('team_cli_preview_');
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      cliExecutableResolver: (cli) =>
          cli == CliTool.claude ? '/opt/bin/claude' : cli.value,
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );
    const member = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
    const team = TeamProfile(
      id: 'claude-team',
      name: 'Claude Team',
      cli: CliTool.claude,
      members: [member],
    );
    await _repo(base).saveTeamProfiles([team]);
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
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
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
    const team = TeamProfile(
      id: 'claude-team',
      name: 'Claude Team',
      cli: CliTool.claude,
      members: [member],
    );
    await repo.saveTeamProfiles([team]);
    await cubit.load();

    await cubit.updateMember(
      'developer',
      member.copyWith(provider: 'moonshot', model: 'kimi-k2'),
    );

    final settingsFile = File(
      p.join(
        base.path,
        'workspace',
        'workspaces',
        'workspace-1',
        'sessions',
        configProfileAdhocSessionId,
        'runtime',
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
      cubit.state.selectedTeam!.members.any((m) => m.id == 'team-lead'),
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
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'claude',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
      launcher: (_, member) async => launched.add(member.name),
    );

    const team = TeamProfile(
      id: 'claude-team',
      name: 'Claude Team',
      cli: CliTool.claude,
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'developer', name: 'developer'),
      ],
    );
    await repo.saveTeamProfiles([team]);
    await cubit.load(awaitProfiles: true);

    await cubit.launchSelectedTeam();

    expect(launched, ['team-lead', 'developer']);
    final teamRoot = p.join(base.path, 'identities-runtime', 'claude-team');
    expect(await Directory(teamRoot).exists(), isTrue);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test('load creates runtime profile directories for default team', () async {
    final base = await Directory.systemTemp.createTemp('team_profile_load_');
    final cubit = LaunchProfileCubit(
      repository: _repo(base),
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
      appDataBasePath: base.path,
      configProfileService: ConfigProfileService(basePath: base.path),
    );

    await cubit.load(awaitProfiles: true);

    final teamRoot = p.join(base.path, 'identities-runtime', 'default-team');
    expect(await Directory(teamRoot).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isFalse);

    await _drainAndCloseTeamCubit(cubit);
    await base.delete(recursive: true);
  });

  test(
    'bindClaudeProviderForTeamsWithoutBinding sets claude team provider',
    () async {
      final dir = await Directory.systemTemp.createTemp('team-bind-provider-');
      final repo = _repo(dir);
      final cubit = LaunchProfileCubit(
        repository: repo,
        sessionRepository: SessionRepository(),
        reloadWorkspaces: () async {},
        executableResolver: () => 'claude',
        pluginLinker: _RecordingPluginLinker(),
      );

      const team = TeamProfile(
        id: 'default-team',
        name: 'Default Team',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await repo.saveTeamProfiles([team]);
      await cubit.load();

      await cubit.bindClaudeProviderForTeamsWithoutBinding('deepseek');

      expect(cubit.state.selectedTeam!.providerIdsByTool['claude'], 'deepseek');
      final reloaded = await repo.loadTeamProfiles();
      expect(reloaded.single.providerIdsByTool['claude'], 'deepseek');

      await _drainAndCloseTeamCubit(cubit);
      await dir.delete(recursive: true);
    },
  );

  test(
    'bindClaudeProviderForTeamsWithoutBinding keeps existing binding',
    () async {
      final dir = await Directory.systemTemp.createTemp('team-bind-existing-');
      final repo = _repo(dir);
      final cubit = LaunchProfileCubit(
        repository: repo,
        sessionRepository: SessionRepository(),
        reloadWorkspaces: () async {},
        executableResolver: () => 'claude',
        pluginLinker: _RecordingPluginLinker(),
      );

      const team = TeamProfile(
        id: 'default-team',
        name: 'Default Team',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        providerIdsByTool: {'claude': 'official'},
      );
      await repo.saveTeamProfiles([team]);
      await cubit.load();

      await cubit.bindClaudeProviderForTeamsWithoutBinding('deepseek');

      expect(cubit.state.selectedTeam!.providerIdsByTool['claude'], 'official');

      await _drainAndCloseTeamCubit(cubit);
      await dir.delete(recursive: true);
    },
  );

  test('reorderTeams persists sortOrder for all teams', () async {
    final dir = await Directory.systemTemp.createTemp('team-reorder-');
    final repo = _repo(dir);
    final cubit = LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(),
      reloadWorkspaces: () async {},
      executableResolver: () => 'flashskyai',
      pluginLinker: _RecordingPluginLinker(),
    );

    await repo.saveTeamProfiles(const [
      TeamProfile(
        id: 'first',
        name: 'First',
        createdAt: 1,
        members: [TeamMemberConfig(id: 'm', name: 'm')],
      ),
      TeamProfile(
        id: 'second',
        name: 'Second',
        createdAt: 2,
        members: [TeamMemberConfig(id: 'm', name: 'm')],
      ),
      TeamProfile(
        id: 'third',
        name: 'Third',
        createdAt: 3,
        members: [TeamMemberConfig(id: 'm', name: 'm')],
      ),
    ]);
    await cubit.load();

    await cubit.reorderTeams(0, 3);

    expect(cubit.state.teams.map((t) => t.name).toList(), [
      'Second',
      'Third',
      'First',
    ]);
    expect(cubit.state.teams.map((t) => t.sortOrder).toList(), [1, 2, 3]);

    final reloaded = await repo.loadTeamProfiles();
    expect(reloaded.map((t) => t.name).toList(), ['Second', 'Third', 'First']);

    await _drainAndCloseTeamCubit(cubit);
    await dir.delete(recursive: true);
  });
}
