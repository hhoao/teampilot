import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/config_profile_service.dart';
import 'package:teampilot/services/flashskyai_storage_roots.dart';
import 'package:teampilot/services/team_launch_environment_builder.dart';

Future<void> _writeProvidersCatalog(
  String basePath,
  List<AppProviderConfig> providers,
) async {
  final file = File(p.join(basePath, 'providers', 'providers.json'));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'providers': {for (final provider in providers) provider.id: provider.toJson()},
    }),
  );
}

String _claudeDir(String base, String teamId, String sessionId) => p.join(
  base,
  'config-profiles',
  'teams',
  teamId,
  sessionId,
  'claude',
);

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('team_launch_env_');
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
  });

  test('flashskyai team launch returns flashskyai env only', () async {
    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      team: const TeamConfig(id: 'team-a', name: 'Team A'),
      llmConfigPathOverride: '/global/llm_config.json',
    );

    expect(env, isNotNull);
    expect(env!.keys, ['FLASHSKYAI_CONFIG_DIR', 'LLM_CONFIG_PATH']);
    expect(
      env['FLASHSKYAI_CONFIG_DIR'],
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        configProfileAdhocSessionId,
        'flashskyai',
      ),
    );
    expect(env.containsKey('CLAUDE_CONFIG_DIR'), isFalse);
  });

  test('team launch uses resolved storage roots when provided', () async {
    final remoteRoot = p.join(base.path, 'remote-app');

    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      team: const TeamConfig(id: 'team-a', name: 'Team A'),
      storageRootsResolver: () async => StorageRootsSnapshot(
        storageIsRemote: true,
        teampilotRoot: remoteRoot,
        teamsUiDir: p.join(remoteRoot, 'teams'),
        cliTeamsDir: '/remote/.flashskyai/teams',
        skillsRoot: p.join(remoteRoot, 'skills'),
        skillBackupsDir: p.join(remoteRoot, 'skill-backups'),
        cliSkillsDir: '/remote/.flashskyai/skills',
        cliAgentsDir: '/remote/.flashskyai/agents',
        appProjectsDir: p.join(remoteRoot, 'projects'),
        skillReposConfigPath: p.join(remoteRoot, 'skills.json'),
      ),
    );

    expect(
      env!['FLASHSKYAI_CONFIG_DIR'],
      p.join(
        remoteRoot,
        'config-profiles',
        'teams',
        'team-a',
        configProfileAdhocSessionId,
        'flashskyai',
      ),
    );
  });

  test('codex team returns CODEX_HOME only', () async {
    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      team: const TeamConfig(id: 'team-a', name: 'Team A', cli: TeamCli.codex),
    );

    expect(env!.keys, ['CODEX_HOME']);
    expect(
      env['CODEX_HOME'],
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        configProfileAdhocSessionId,
        'codex',
      ),
    );
  });

  test('claude team launch passes members to roster generation', () async {
    const sessionId = 'sess-roster-1';
    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      runtimeTeamId: sessionId,
      workingDirectory: '/workspace/team-a',
      team: const TeamConfig(
        id: 'team-a',
        name: 'Team A',
        cli: TeamCli.claude,
        members: [
          TeamMemberConfig(id: 'lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
        ],
      ),
    );

    final claudeDir = _claudeDir(base.path, 'team-a', sessionId);
    expect(env!['CLAUDE_CONFIG_DIR'], claudeDir);

    final roster = File(p.join(claudeDir, 'teams', sessionId, 'config.json'));
    final decoded =
        jsonDecode(await roster.readAsString()) as Map<String, Object?>;
    final members = decoded['members'] as List<Object?>;
    expect(members.map((m) => (m as Map)['name']), ['team-lead', 'developer']);
    expect((members.last as Map)['model'], 'sonnet');
  });

  test(
    'claude launch resolves member provider when team tool binding is empty',
    () async {
      await _writeProvidersCatalog(base.path, [
        AppProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          apiKey: 'sk-member-only',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-default',
          enabledTools: const [AppProviderTool.claude],
        ),
      ]);

      const sessionId = 'sess-member-prov-only';
      await TeamLaunchEnvironmentBuilder.build(
        appDataBasePath: base.path,
        runtimeTeamId: sessionId,
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: TeamCli.claude,
          members: [
            TeamMemberConfig(
              id: 'dev',
              name: 'developer',
              provider: 'deepseek',
              model: 'deepseek-v4-pro[1m]',
            ),
          ],
        ),
        member: const TeamMemberConfig(
          id: 'dev',
          name: 'developer',
          provider: 'deepseek',
          model: 'deepseek-v4-pro[1m]',
        ),
      );

      final settingsFile = File(
        p.join(_claudeDir(base.path, 'team-a', sessionId), 'settings.json'),
      );
      final teamEnv =
          (jsonDecode(await settingsFile.readAsString())
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(teamEnv['ANTHROPIC_API_KEY'], 'sk-member-only');
      expect(teamEnv['ANTHROPIC_BASE_URL'], contains('deepseek.com'));

      final memberFile = File(
        p.join(
          _claudeDir(base.path, 'team-a', sessionId),
          'settings',
          'developer.json',
        ),
      );
      final memberEnv =
          (jsonDecode(await memberFile.readAsString())
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(memberEnv['ANTHROPIC_API_KEY'], 'sk-member-only');
      expect(memberEnv['ANTHROPIC_MODEL'], 'deepseek-v4-pro[1m]');
    },
  );

  test('claude team launch writes settings from providers.json', () async {
    await _writeProvidersCatalog(base.path, [
      AppProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        apiKey: 'sk-test',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-v4-pro[1m]',
        enabledTools: const [AppProviderTool.claude],
      ),
    ]);

    await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      team: const TeamConfig(
        id: 'team-a',
        name: 'Team A',
        cli: TeamCli.claude,
        providerIdsByTool: {'claude': 'deepseek'},
      ),
    );

    final settingsFile = File(
      p.join(
        _claudeDir(base.path, 'team-a', configProfileAdhocSessionId),
        'settings.json',
      ),
    );
    final settings =
        jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;
    final env = settings['env'] as Map<String, Object?>;
    expect(env['ANTHROPIC_API_KEY'], 'sk-test');
    expect(env['ANTHROPIC_MODEL'], 'deepseek-v4-pro[1m]');
    expect(settings['teammateMode'], 'in-process');
  });

  test(
    'claude member launch returns shared config dir and settings file',
    () async {
      const sessionId = '00000000-0000-4000-8000-000000000001';
      await _writeProvidersCatalog(base.path, [
        AppProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          apiKey: 'sk-test',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-default',
          enabledTools: const [AppProviderTool.claude],
        ),
      ]);

      final env = await TeamLaunchEnvironmentBuilder.build(
        appDataBasePath: base.path,
        runtimeTeamId: sessionId,
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: TeamCli.claude,
          providerIdsByTool: {'claude': 'deepseek'},
          members: [
            TeamMemberConfig(id: 'lead', name: 'team-lead', model: 'opus'),
            TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
          ],
        ),
        member: const TeamMemberConfig(
          id: 'dev',
          name: 'developer',
          model: 'sonnet',
        ),
      );

      final claudeDir = _claudeDir(base.path, 'team-a', sessionId);
      final developerSettings = p.join(claudeDir, 'settings', 'developer.json');
      expect(env!['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(
        env[ConfigProfileService.claudeSettingsFileEnvKey],
        developerSettings,
      );

      final settingsEnv =
          (jsonDecode(await File(developerSettings).readAsString())
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(
        settingsEnv['ANTHROPIC_BASE_URL'],
        contains('deepseek.com'),
      );
      expect(settingsEnv['ANTHROPIC_MODEL'], 'sonnet');
    },
  );

  test(
    'claude member settings use member provider over team provider',
    () async {
      await _writeProvidersCatalog(base.path, [
        AppProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          apiKey: 'sk-deepseek',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-default',
          enabledTools: const [AppProviderTool.claude],
        ),
        AppProviderConfig(
          id: 'moonshot',
          name: 'Moonshot',
          apiKey: 'sk-moonshot',
          baseUrl: 'https://api.moonshot.example/anthropic',
          defaultModel: 'moonshot-default',
          enabledTools: const [AppProviderTool.claude],
        ),
      ]);

      const sessionId = 'sess-multi-prov';
      await TeamLaunchEnvironmentBuilder.build(
        appDataBasePath: base.path,
        runtimeTeamId: sessionId,
        team: const TeamConfig(
          id: 'team-a',
          name: 'Team A',
          cli: TeamCli.claude,
          providerIdsByTool: {'claude': 'deepseek'},
          members: [
            TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
            TeamMemberConfig(
              id: 'reviewer',
              name: 'reviewer',
              provider: 'moonshot',
              model: 'opus',
            ),
          ],
        ),
        member: const TeamMemberConfig(
          id: 'dev',
          name: 'developer',
          provider: 'deepseek',
          model: 'sonnet',
        ),
      );

      Future<Map<String, Object?>> readEnv(String memberName) async {
        final settingsFile = File(
          p.join(
            _claudeDir(base.path, 'team-a', sessionId),
            'settings',
            '$memberName.json',
          ),
        );
        return (jsonDecode(await settingsFile.readAsString())
                as Map<String, Object?>)['env']
            as Map<String, Object?>;
      }

      expect((await readEnv('developer'))['ANTHROPIC_API_KEY'], 'sk-deepseek');
      expect((await readEnv('reviewer'))['ANTHROPIC_API_KEY'], 'sk-moonshot');
    },
  );

  test('empty team id keeps legacy llm override fallback', () async {
    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      team: const TeamConfig(id: '', name: ''),
      llmConfigPathOverride: '/global/llm_config.json',
    );

    expect(env, {'LLM_CONFIG_PATH': '/global/llm_config.json'});
  });
}
