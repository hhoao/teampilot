import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/project_profile_repository.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/storage_resolver.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

StorageRootsSnapshot _roots(String basePath) => StorageRootsSnapshot(
	  storageIsRemote: false,
	  teampilotRoot: basePath,
	  teamsUiDir: p.join(basePath, 'teams'),
	  skillsRoot: p.join(basePath, 'skills', 'installed'),
	  skillBackupsDir: p.join(basePath, 'skills', 'backups'),
	  workspaceDir: p.join(basePath, 'workspace'),
	  skillReposConfigPath: p.join(basePath, 'skills', 'repos.json'),
	  pluginsRoot: p.join(basePath, 'plugins', 'installed'),
	  pluginBackupsDir: p.join(basePath, 'plugins', 'backups'),
	  pluginsJsonPath: p.join(basePath, 'plugins', 'plugins.json'),
	  pluginMarketplacesConfigPath: p.join(
	    basePath,
	    'plugins',
	    'marketplaces.json',
	  ),
	  pluginMarketplaceCacheDir: p.join(basePath, 'plugins', 'marketplace-cache'),
	  pluginExternalCacheDir: p.join(basePath, 'plugins', 'external-cache'),
	  mcpServersJsonPath: p.join(basePath, 'mcp', 'mcp_servers.json'),
	  mcpRegistrySourcesConfigPath: p.join(
	    basePath,
	    'mcp',
	    'registry_sources.json',
	  ),
	);

/// Creates an [InMemoryFilesystem]-backed [CliPresetsRepository] seeded with
/// a single preset so that [SessionLifecycleService] can resolve it via
/// [ProjectProfile.activePresetId].
Future<CliPresetsRepository> _seededPresetsRepo({
  required String presetId,
  required String name,
  required CliTool cli,
  required String provider,
  required String model,
  String effort = '',
}) async {
  final fs = InMemoryFilesystem();
  final presetsPath = '/cli-presets.json';
  final preset = CliPreset(
    id: presetId,
    name: name,
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    createdAt: 1,
    updatedAt: 1,
  );
  final repo = CliPresetsRepository(fs: fs, presetsPath: presetsPath);
  await repo.save([preset]);
  return repo;
}

void main() {
  late Directory base;
  late RuntimeLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_standalone_');
    layout = RuntimeLayout(teampilotRoot: base.path);
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
    tearDownTestAppStorage();
  });

  SessionLifecycleService service({
    ProjectProfileRepository? projectProfileRepository,
    CliPresetsRepository? cliPresetsRepository,
  }) => SessionLifecycleService(
    appDataBasePath: base.path,
    storageRootsResolver: () async => _roots(base.path),
    projectProfileRepository: projectProfileRepository,
    cliPresetsRepository: cliPresetsRepository,
  );

  test(
    'prepareShellLaunch loads persisted profile from repository',
    () async {
      const projectId = 'personal-proj';
      const sessionId = 'personal-sess';
      final repo = ProjectProfileRepository(rootDir: base.path);
      // Seed a preset for flashskyai so the resolved member/provider/model/cli
      // come from the active preset instead of the (now-removed) profile fields.
      final presetsRepo = await _seededPresetsRepo(
        presetId: 'preset-fs',
        name: 'FlashskyAI Work',
        cli: CliTool.flashskyai,
        provider: 'custom-provider',
        model: 'opus',
      );
      await repo.save(
        ProjectProfile(
          projectId: projectId,
          activePresetId: 'preset-fs',
          agent: const ProjectAgentConfig(
            agent: 'persisted-agent',
          ),
        ),
      );
      const project = AppProject(
        projectId: projectId,
        primaryPath: '/work/personal',
        teamId: '',
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        projectId: projectId,
        primaryPath: '/work/personal',
        sessionTeam: '',
        createdAt: 1,
      );

      final shellLaunch = await service(
        projectProfileRepository: repo,
        cliPresetsRepository: presetsRepo,
      ).prepareShellLaunch(
        session: session,
        project: project,
      );

      expect(shellLaunch.launchContext.member.model, 'opus');
      expect(shellLaunch.launchContext.member.agent, 'persisted-agent');
      expect(shellLaunch.launchContext.member.provider, 'custom-provider');
      expect(shellLaunch.launchContext.team.cli, CliTool.flashskyai);
    },
  );

  test(
    'personal session prepareLaunch returns CLAUDE_CONFIG_DIR under standalone/',
    () async {
      const projectId = 'personal-proj';
      const sessionId = 'personal-sess';
      const profile = ProjectProfile(
        projectId: projectId,
        agent: ProjectAgentConfig(agent: 'solo'),
      );
      const project = AppProject(
        projectId: projectId,
        primaryPath: '/work/personal',
        teamId: '',
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        projectId: projectId,
        primaryPath: '/work/personal',
        sessionTeam: '',
        createdAt: 1,
      );

      final plan = await service().prepareLaunch(
        session: session,
        project: project,
        profile: profile,
      );

      final claudeDir = layout.sessionRuntimeToolDir(
        projectId,
        sessionId,
        'claude',
      );
      expect(plan.env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(plan.memberConfigDir, claudeDir);
      expect(plan.taskId, sessionId);
      expect(plan.cliTeamName, sessionId);
      expect(plan.resume, isFalse);
      expect(plan.resolvedRoots, contains(claudeDir));
    },
  );

  test(
    'prepareShellLaunch includes CliLaunchContext for personal sessions',
    () async {
      const projectId = 'personal-proj';
      const sessionId = 'personal-sess';
      // Seed a claude preset so the resolved model/provider/cli match.
      final presetsRepo = await _seededPresetsRepo(
        presetId: 'preset-claude',
        name: 'Claude Work',
        cli: CliTool.claude,
        provider: 'anthropic',
        model: 'sonnet',
      );
      const profile = ProjectProfile(
        projectId: projectId,
        activePresetId: 'preset-claude',
        agent: ProjectAgentConfig(
          agent: 'solo',
        ),
      );
      const project = AppProject(
        projectId: projectId,
        primaryPath: '/work/personal',
        teamId: '',
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        projectId: projectId,
        primaryPath: '/work/personal',
        sessionTeam: '',
        createdAt: 1,
      );

      final shellLaunch = await service(
        cliPresetsRepository: presetsRepo,
      ).prepareShellLaunch(
        session: session,
        project: project,
        profile: profile,
      );

      expect(shellLaunch.sessionTeam, sessionId);
      expect(shellLaunch.launchContext.member.model, 'sonnet');
      expect(shellLaunch.launchContext.member.agent, 'solo');
      expect(shellLaunch.launchContext.member.provider, 'anthropic');
      expect(shellLaunch.launchContext.team.cli, CliTool.claude);
      expect(shellLaunch.plan.env['CLAUDE_CONFIG_DIR'], isNotEmpty);
    },
  );

  test(
    'personal session resumes under its pinned CLI even after the active '
    'preset switches to another CLI',
    () async {
      const projectId = 'personal-proj';
      const sessionId = 'personal-sess';
      // The project's active preset is now Codex, but the session was created
      // with (and is pinned to) Claude. Switching the active CLI must not
      // re-bind the existing session: its launch + resume probe must still
      // target Claude, or the prior transcript would be orphaned (data loss).
      final fs = InMemoryFilesystem();
      final presetsRepo = CliPresetsRepository(
        fs: fs,
        presetsPath: '/cli-presets.json',
      );
      await presetsRepo.save([
        CliPreset(
          id: 'preset-claude',
          name: 'Claude Work',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'sonnet',
          createdAt: 1,
          updatedAt: 1,
        ),
        CliPreset(
          id: 'preset-codex',
          name: 'Codex Work',
          cli: CliTool.codex,
          provider: 'openai',
          model: 'gpt',
          createdAt: 2,
          updatedAt: 2,
        ),
      ]);
      const profile = ProjectProfile(
        projectId: projectId,
        activePresetId: 'preset-codex',
      );
      const project = AppProject(
        projectId: projectId,
        primaryPath: '/work/personal',
        teamId: '',
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        projectId: projectId,
        primaryPath: '/work/personal',
        sessionTeam: '',
        cli: CliTool.claude,
        createdAt: 1,
      );

      final plan = await service(
        cliPresetsRepository: presetsRepo,
      ).prepareLaunch(
        session: session,
        project: project,
        profile: profile,
      );

      final claudeDir = layout.sessionRuntimeToolDir(
        projectId,
        sessionId,
        'claude',
      );
      // Resolved under Claude (session.cli), not Codex (active preset).
      expect(plan.env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(plan.memberConfigDir, claudeDir);
      expect(
        plan.resolvedRoots.any((r) => r.contains('codex')),
        isFalse,
        reason: 'must not probe the active preset CLI (codex) for resume',
      );
    },
  );

  test(
    'prepareShellLaunch throws without team and member for non-personal sessions',
    () async {
      final session = AppSession(
        sessionId: 'team-sess',
        projectId: 'proj',
        primaryPath: '/work/team',
        sessionTeam: 'tid',
        cliTeamName: 'tid-1',
        createdAt: 1,
      );

      expect(
        () => service().prepareShellLaunch(session: session, team: null),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('destroyStandaloneCliState removes standalone session tree', () async {
    const projectId = 'personal-proj';
    const sessionId = 'personal-sess';
    final sessionRoot = p.dirname(
      layout.sessionRuntimeToolDir(projectId, sessionId, 'claude'),
    );
    await File(
      p.join(sessionRoot, 'claude', 'projects', 'bucket', '$sessionId.jsonl'),
    ).create(recursive: true);

    expect(await Directory(sessionRoot).exists(), isTrue);
    await service().destroyStandaloneCliState(
      projectId: projectId,
      sessionId: sessionId,
    );
    expect(await Directory(sessionRoot).exists(), isFalse);
  });
}
