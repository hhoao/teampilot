import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/storage/storage_resolver.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import '../../support/post_frame_test_harness.dart';

StorageRootsSnapshot _roots(String basePath) => StorageRootsSnapshot(
  storageIsRemote: false,
  teampilotRoot: basePath,
  launchProfilesDir: p.join(basePath, 'launch-profiles'),
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

const _workspaceId = 'workspace-1';

AppSession _session({
  String id = 'session-1',
  AppSessionLaunchState launchState = AppSessionLaunchState.created,
}) => AppSession(
  sessionId: id,
  workspaceId: _workspaceId,
  primaryPath: '/work/workspace',
  sessionTeam: 'team-a',
  launchState: launchState,
  createdAt: 1,
  updatedAt: 1,
);

Future<void> _writeProvidersCatalog(
  String basePath,
  List<AppProviderConfig> providers,
) async {
  final file = File(p.join(basePath, 'providers', 'claude', 'providers.json'));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'providers': {
        for (final provider in providers) provider.id: provider.toJson(),
      },
    }),
  );
}

void main() {
  late Directory base;
  late RuntimeLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_');
    layout = RuntimeLayout(teampilotRoot: base.path);
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
    'prepareLaunch returns env and non-resume plan for a new session',
    () async {
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.claude,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      );

      final memberDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'session-1',
        'claude',
      );
      expect(plan.resume, isFalse);
      expect(plan.taskId, 'session-1');
      expect(plan.cliTeamName, 'session-1');
      expect(plan.memberConfigDir, memberDir);
      expect(plan.env['CLAUDE_CONFIG_DIR'], memberDir);
      expect(plan.env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');
      expect(plan.env['CLAUDE_CODE_NO_FLICKER'], '1');
      expect(plan.env.containsKey('TEAMPILOT_CLAUDE_SETTINGS_FILE'), isTrue);
      expect(plan.resolvedRoots, contains(memberDir));
    },
  );

  test(
    'prepareLaunch for flashskyai team uses flashskyai member dir and env',
    () async {
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      );

      final memberDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'session-1',
        'flashskyai',
      );
      expect(plan.resume, isFalse);
      expect(plan.taskId, 'session-1');
      expect(plan.cliTeamName, 'session-1');
      expect(plan.memberConfigDir, memberDir);
      expect(
        plan.env[FlashskyaiConfigProfileCapability.configDirEnvKey],
        memberDir,
      );
      expect(
        plan.env[FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey],
        memberDir,
      );
      expect(
        plan.env['LLM_CONFIG_PATH'],
        p.join(base.path, 'cli-defaults', 'flashskyai', 'llm_config.json'),
      );
      expect(plan.resolvedRoots, contains(memberDir));
    },
  );

  test(
    'prepareLaunch cursor mixed mode uses HOME as memberConfigDir',
    () async {
      const member = TeamMemberConfig(id: 'planner', name: 'Planner');
      final plan = await service().prepareLaunch(
        session: _session(id: 'mixed-session'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
        busIdleUrl: 'http://127.0.0.1:5050/idle',
      );

      final cursorDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'mixed-session',
        'cursor',
        memberId: ClaudeTeamRosterService.safeClaudePathSegment('planner'),
      );
      final memberHome = p.join(cursorDir, 'home');
      expect(plan.memberConfigDir, memberHome);
      expect(plan.env['HOME'], memberHome);
      expect(plan.resolvedRoots, contains(memberHome));
    },
  );

  test(
    'cursor: fresh launch does not resume and is not pinned (postCaptured)',
    () async {
      // No cursor chat store yet → cursor mints its own chat (no --resume,
      // no --session-id), and the conversation is treated as fresh.
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.cursor,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        memberBinding: const SessionMemberBinding(
          rosterMemberId: 'team-lead',
          taskId: 'session-1',
        ),
      );
      expect(plan.resume, isFalse);
      expect(plan.resumeSessionId, isNull);
      expect(plan.createSessionId, isNull);
      expect(plan.isFreshConversation, isTrue);
    },
  );

  test(
    'prepareLaunch mixed member claude override uses claude profile dirs',
    () async {
      const member = TeamMemberConfig(
        id: 'team-lead',
        name: 'team-lead',
        cli: CliTool.claude,
      );
      final plan = await service().prepareLaunch(
        session: _session(id: 'mixed-session'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
      );

      final claudeDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'mixed-session',
        'claude',
        memberId: ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
      );
      final flashskyaiDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'mixed-session',
        'flashskyai',
        memberId: ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
      );
      expect(plan.memberConfigDir, claudeDir);
      expect(plan.env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(
        plan.env.containsKey(FlashskyaiConfigProfileCapability.configDirEnvKey),
        isFalse,
      );
      expect(claudeDir, isNot(equals(flashskyaiDir)));
    },
  );

  test(
    'prepareLaunch resumes mixed member whose CLI override differs from '
    'team.cli',
    () async {
      const taskId = '8c30aef6-19f6-469c-9b53-bcbda18b6fd2';
      const member = TeamMemberConfig(
        id: 'team-lead',
        name: 'team-lead',
        cli: CliTool.claude,
      );
      final session = _session(
        id: 'mixed-session',
        launchState: AppSessionLaunchState.started,
      ).copyWith(cliTeamName: 'team-a-4');
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        session.primaryPath,
      );
      final transcript = File(
        p.join(
          layout.sessionRuntimeToolDir(
            _workspaceId,
            'mixed-session',
            'claude',
          ),
          'workspaces',
          bucket,
          '$taskId.jsonl',
        ),
      );
      await transcript.parent.create(recursive: true);
      await transcript.writeAsString('{}\n');

      const binding = SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: taskId,
      );
      final plan = await service().prepareLaunch(
        session: session,
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
        memberBinding: binding,
      );

      expect(plan.resume, isTrue);
      expect(plan.taskId, taskId);
    },
  );

  test('prepareLaunch preserves llm override for non-team launches', () async {
    final plan = await SessionLifecycleService(
      appDataBasePath: base.path,
      llmConfigPathOverride: () => '/global/llm_config.json',
      storageRootsResolver: () async => _roots(base.path),
    ).prepareLaunch(session: _session(), team: null);

    expect(plan.env, {'LLM_CONFIG_PATH': '/global/llm_config.json'});
    expect(plan.memberConfigDir, isEmpty);
    expect(plan.resume, isFalse);
  });

  test('hasCliState finds workspace transcripts in member roots', () async {
    final session = _session(launchState: AppSessionLaunchState.started);
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      session.primaryPath,
    );
    final transcript = File(
      p.join(
        layout.sessionRuntimeToolDir(
          _workspaceId,
          session.sessionId,
          'flashskyai',
        ),
        'workspaces',
        bucket,
        '${session.sessionId}.jsonl',
      ),
    );
    await transcript.parent.create(recursive: true);
    await transcript.writeAsString('{}\n');

    expect(
      await service().hasCliState(
        session,
        teamId: 'team-a',
        cli: CliTool.flashskyai,
      ),
      isTrue,
    );
    final plan = await service().prepareLaunch(
      session: session,
      team: const TeamProfile(
        id: 'team-a',
        name: 'Team A',
        cli: CliTool.flashskyai,
      ),
    );
    expect(plan.resume, isTrue);
  });

  test(
    'hasCliState probes taskId transcript under cliTeamName runtime dir',
    () async {
      const taskId = '11111111-1111-1111-1111-111111111111';
      final session = _session(
        launchState: AppSessionLaunchState.started,
      ).copyWith(cliTeamName: 'team-a-3');
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        session.primaryPath,
      );
      final transcript = File(
        p.join(
          layout.sessionRuntimeToolDir(
            _workspaceId,
            session.sessionId,
            'flashskyai',
          ),
          'workspaces',
          bucket,
          '$taskId.jsonl',
        ),
      );
      await transcript.parent.create(recursive: true);
      await transcript.writeAsString('{}\n');

      final binding = const SessionMemberBinding(
        rosterMemberId: 'lead',
        taskId: taskId,
      );
      expect(
        await service().hasCliState(
          session,
          teamId: 'team-a',
          cli: CliTool.flashskyai,
          memberBinding: binding,
        ),
        isTrue,
      );
      final plan = await service().prepareLaunch(
        session: session,
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
        ),
        memberBinding: binding,
      );
      expect(plan.resume, isTrue);
      expect(plan.taskId, taskId);
      expect(plan.cliTeamName, 'team-a-3');
    },
  );

  test(
    'prepareLaunch writes Claude provider settings for launched member',
    () async {
      await _writeProvidersCatalog(base.path, [
        AppProviderConfig(
          id: 'deepseek',
          cli: CliTool.claude,
          name: 'DeepSeek',
          apiKey: 'sk-test',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-default',
        ),
      ]);
      final plan = await service().prepareLaunch(
        session: _session(id: 'claude-session-1'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.claude,
          providerIdsByTool: {'claude': 'deepseek'},
          members: [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead', model: 'opus'),
            TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
          ],
        ),
        member: const TeamMemberConfig(
          id: 'dev',
          name: 'developer',
          model: 'sonnet',
        ),
      );

      final developerSettings = p.join(
        plan.memberConfigDir,
        'settings',
        'dev.json',
      );
      expect(plan.env['CLAUDE_CONFIG_DIR'], plan.memberConfigDir);
      expect(
        plan.env[ClaudeConfigProfileCapability.settingsFileEnvKey],
        developerSettings,
      );
      final settingsEnv =
          (jsonDecode(await File(developerSettings).readAsString())
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(settingsEnv['ANTHROPIC_BASE_URL'], contains('deepseek.com'));
      expect(settingsEnv['ANTHROPIC_MODEL'], 'sonnet');
    },
  );

  test('destroyCliState removes the session runtime tree', () async {
    final sessionRoot = layout.workspace.sessionRuntimeDir(
      _workspaceId,
      'session-1',
    );
    await File(
      p.join(
        sessionRoot,
        'flashskyai',
        'workspaces',
        'bucket',
        'session-1.jsonl',
      ),
    ).create(recursive: true);
    await File(
      p.join(
        sessionRoot,
        'claude',
        ClaudeConfigProfileCapability.metadataFileName,
      ),
    ).create(recursive: true);

    expect(await Directory(sessionRoot).exists(), isTrue);
    await service().destroyCliState(
      workspaceId: _workspaceId,
      teamId: 'team-a',
      sessionId: 'session-1',
    );

    expect(await Directory(sessionRoot).exists(), isFalse);
  });

  test('destroyCliToolState removes the whole team runtime tree', () async {
    final teamRoot = layout.identityRuntimeDir('team-a');
    await File(
      p.join(teamRoot, 'flashskyai', 'skills', 'demo'),
    ).create(recursive: true);

    expect(await Directory(teamRoot).exists(), isTrue);
    await service().destroyCliToolState('team-a');

    expect(await Directory(teamRoot).exists(), isFalse);
  });
}
