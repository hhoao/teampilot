import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_scope.dart';
import 'package:teampilot/services/storage/storage_resolver.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

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

AppSession _session({
  String id = 'session-1',
  AppSessionLaunchState launchState = AppSessionLaunchState.created,
}) => AppSession(
  sessionId: id,
  projectId: 'project-1',
  primaryPath: '/work/project',
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
  late CliDataLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_');
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
    'prepareLaunch returns env and non-resume plan for a new session',
    () async {
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.claude,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      );

      final memberDir = layout.memberToolDir('team-a', 'session-1', 'claude');
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
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      );

      final memberDir = layout.memberToolDir(
        'team-a',
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
        p.join(base.path, 'config-profiles', 'flashskyai', 'llm_config.json'),
      );
      expect(plan.resolvedRoots, contains(memberDir));
    },
  );

  test(
    'prepareLaunch cursor mixed mode uses HOME as memberConfigDir',
    () async {
      const member = TeamMemberConfig(id: 'planner', name: 'Planner');
      final scopedSessionId = mixedModeMemberScopeSessionId(
        p.context,
        'mixed-session',
        member,
      );
      final plan = await service().prepareLaunch(
        session: _session(id: 'mixed-session'),
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
        busIdleUrl: 'http://127.0.0.1:5050/idle',
      );

      final cursorDir = layout.memberToolDir(
        'team-a',
        scopedSessionId,
        'cursor',
      );
      final memberHome = p.join(cursorDir, 'home');
      expect(plan.memberConfigDir, memberHome);
      expect(plan.env['HOME'], memberHome);
      expect(plan.resolvedRoots, contains(memberHome));
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
      final scopedSessionId = mixedModeMemberScopeSessionId(
        p.context,
        'mixed-session',
        member,
      );
      final plan = await service().prepareLaunch(
        session: _session(id: 'mixed-session'),
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
      );

      // Mixed members each own an isolated CONFIG_DIR nested under the session
      // (members/<cliTeamName>/<memberId>/<tool>) so the teammate-bus MCP config
      // and X-Member identity cannot be clobbered by a sibling member launch.
      final claudeDir = layout.memberToolDir(
        'team-a',
        scopedSessionId,
        'claude',
      );
      final flashskyaiDir = layout.memberToolDir(
        'team-a',
        scopedSessionId,
        'flashskyai',
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
      // Regression: a mixed team JSON without a top-level `cli` defaults
      // team.cli to flashskyai, while members override `cli: claude`. The
      // member launches (and stores transcripts) under its claude scope, so the
      // resume probe must follow `member.cliWithin(team)` — not team.cli — or it
      // falls back to `--session-id`, which the running CLI rejects as
      // "Session ID ... is already in use".
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
      final scopedSessionId = mixedModeMemberScopeSessionId(
        p.context,
        'team-a-4',
        member,
      );
      final bucket = CliDataLayout.projectBucketForPrimaryPath(
        session.primaryPath,
      );
      // Transcript lives under the member's *claude* scope, matching how the
      // member actually launched.
      final transcript = File(
        p.join(
          layout.memberToolDir('team-a', scopedSessionId, 'claude'),
          'projects',
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
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai, // team default; member overrides to claude
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

  test('hasCliState finds project transcripts in member roots', () async {
    final session = _session(launchState: AppSessionLaunchState.started);
    final bucket = CliDataLayout.projectBucketForPrimaryPath(
      session.primaryPath,
    );
    final transcript = File(
      p.join(
        layout.memberToolDir('team-a', session.sessionId, 'flashskyai'),
        'projects',
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
      team: const TeamConfig(
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
      final bucket = CliDataLayout.projectBucketForPrimaryPath(
        session.primaryPath,
      );
      final transcript = File(
        p.join(
          layout.memberToolDir('team-a', 'team-a-3', 'flashskyai'),
          'projects',
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
        team: const TeamConfig(
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
        team: const TeamConfig(
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

  test('destroyCliState removes the member profile tree', () async {
    final memberRoot = p.dirname(
      layout.memberToolDir('team-a', 'session-1', 'flashskyai'),
    );
    await File(
      p.join(memberRoot, 'flashskyai', 'projects', 'bucket', 'session-1.jsonl'),
    ).create(recursive: true);
    await File(
      p.join(
        memberRoot,
        'claude',
        ClaudeConfigProfileCapability.metadataFileName,
      ),
    ).create(recursive: true);

    expect(await Directory(memberRoot).exists(), isTrue);
    await service().destroyCliState(teamId: 'team-a', sessionId: 'session-1');

    expect(await Directory(memberRoot).exists(), isFalse);
  });

  test(
    'destroyCliState can remove a legacy runtime member directory',
    () async {
      final memberRoot = p.dirname(
        layout.memberToolDir('team-a', 'legacy-runtime', 'flashskyai'),
      );
      await File(
        p.join(
          memberRoot,
          'flashskyai',
          'projects',
          'bucket',
          'session-1.jsonl',
        ),
      ).create(recursive: true);

      await service().destroyCliState(
        teamId: 'team-a',
        sessionId: 'session-1',
        runtimeSessionId: 'legacy-runtime',
      );

      expect(await Directory(memberRoot).exists(), isFalse);
    },
  );

  test('destroyCliToolState removes the whole team profile tree', () async {
    final teamRoot = p.dirname(layout.teamToolDir('team-a', 'flashskyai'));
    await File(
      p.join(teamRoot, 'members', 'session-1', 'flashskyai', 'state.json'),
    ).create(recursive: true);
    await File(
      p.join(teamRoot, 'flashskyai', 'skills', 'demo'),
    ).create(recursive: true);

    expect(await Directory(teamRoot).exists(), isTrue);
    await service().destroyCliToolState('team-a');

    expect(await Directory(teamRoot).exists(), isFalse);
  });
}
