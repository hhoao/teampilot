import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/storage_resolver.dart';

import '../../support/post_frame_test_harness.dart';

StorageRootsSnapshot _roots(String basePath) => StorageRootsSnapshot(
  storageIsRemote: false,
  teampilotRoot: basePath,
  teamsUiDir: p.join(basePath, 'teams'),
  skillsRoot: p.join(basePath, 'skills', 'installed'),
  skillBackupsDir: p.join(basePath, 'skills', 'backups'),
  appProjectsDir: p.join(basePath, 'projects'),
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

void main() {
  late Directory base;
  late CliDataLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_standalone_');
    layout = CliDataLayout(teampilotRoot: base.path);
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
    tearDownTestAppStorage();
  });

  SessionLifecycleService service() => SessionLifecycleService(
    appDataBasePath: base.path,
    storageRootsResolver: () async => _roots(base.path),
  );

  test(
    'personal session prepareLaunch returns CLAUDE_CONFIG_DIR under standalone/',
    () async {
      const projectId = 'personal-proj';
      const sessionId = 'personal-sess';
      const profile = ProjectProfile(
        projectId: projectId,
        cli: CliTool.claude,
        agent: ProjectAgentConfig(model: 'sonnet', agent: 'solo'),
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

      final claudeDir = layout.standaloneProjectSessionToolDir(
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
      const profile = ProjectProfile(
        projectId: projectId,
        cli: CliTool.claude,
        agent: ProjectAgentConfig(
          model: 'sonnet',
          agent: 'solo',
          provider: 'anthropic',
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

      final shellLaunch = await service().prepareShellLaunch(
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
      layout.standaloneProjectSessionToolDir(projectId, sessionId, 'claude'),
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
