import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/config_profile_service.dart';
import 'package:teampilot/services/flashskyai_storage_roots.dart';
import 'package:teampilot/services/team_launch_environment_builder.dart';

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

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
    expect(env, isNotNull);
    expect(env!.keys, ['FLASHSKYAI_CONFIG_DIR', 'LLM_CONFIG_PATH']);
    expect(env['FLASHSKYAI_CONFIG_DIR'], p.join(teamRoot, 'flashskyai'));
    expect(
      env['LLM_CONFIG_PATH'],
      p.join(
        base.path,
        'config-profiles',
        'common',
        'flashskyai',
        'llm_config.json',
      ),
    );
    expect(env.containsKey('CODEX_HOME'), isFalse);
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

    expect(env!.keys, ['FLASHSKYAI_CONFIG_DIR', 'LLM_CONFIG_PATH']);
    expect(
      env['FLASHSKYAI_CONFIG_DIR'],
      p.join(remoteRoot, 'config-profiles', 'teams', 'team-a', 'flashskyai'),
    );
    expect(
      env['LLM_CONFIG_PATH'],
      p.join(
        remoteRoot,
        'config-profiles',
        'common',
        'flashskyai',
        'llm_config.json',
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
      p.join(base.path, 'config-profiles', 'teams', 'team-a', 'codex'),
    );
  });

  test('claude team launch passes members to roster generation', () async {
    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
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

    final claudeDir = p.join(
      base.path,
      'config-profiles',
      'teams',
      'team-a',
      'claude',
    );
    expect(env!.keys, [
      'CLAUDE_CONFIG_DIR',
      'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS',
    ]);
    expect(env['CLAUDE_CONFIG_DIR'], claudeDir);
    expect(env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');

    final roster = File(p.join(claudeDir, 'teams', 'team-a', 'config.json'));
    final decoded =
        jsonDecode(await roster.readAsString()) as Map<String, Object?>;
    final members = decoded['members'] as List<Object?>;
    expect(members.map((member) => (member as Map<String, Object?>)['name']), [
      'team-lead',
      'developer',
    ]);
    expect((members.last as Map<String, Object?>)['model'], 'sonnet');
    expect((members.last as Map<String, Object?>)['cwd'], '/workspace/team-a');
  });

  test('claude team launch writes settings from selected provider', () async {
    final providerSettings = File(
      p.join(base.path, 'providers', 'claude', 'deepseek', 'settings.json'),
    );
    await providerSettings.parent.create(recursive: true);
    await providerSettings.writeAsString(
      jsonEncode({
        'env': {
          'ANTHROPIC_BASE_URL': 'https://api.deepseek.com/anthropic',
          'ANTHROPIC_AUTH_TOKEN': 'sk-test',
          'ANTHROPIC_MODEL': 'deepseek-v4-pro[1m]',
        },
        'effortLevel': 'high',
      }),
    );

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
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'claude',
        'settings.json',
      ),
    );
    final settings =
        jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;
    final env = settings['env'] as Map<String, Object?>;
    expect(env['ANTHROPIC_BASE_URL'], 'https://api.deepseek.com/anthropic');
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-test');
    expect(env['ANTHROPIC_MODEL'], 'deepseek-v4-pro[1m]');
    expect(env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');
    expect(env['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
    expect(env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'], '1');
    expect(settings['effortLevel'], 'high');
    expect(settings['skipDangerousModePermissionPrompt'], true);
    expect(settings['teammateMode'], 'in-process');
  });

  test(
    'claude member launch returns shared config dir and settings file',
    () async {
      final providerSettings = File(
        p.join(base.path, 'providers', 'claude', 'deepseek', 'settings.json'),
      );
      await providerSettings.parent.create(recursive: true);
      await providerSettings.writeAsString(
        jsonEncode({
          'env': {
            'ANTHROPIC_BASE_URL': 'https://api.deepseek.com/anthropic',
            'ANTHROPIC_MODEL': 'deepseek-default',
          },
        }),
      );

      final env = await TeamLaunchEnvironmentBuilder.build(
        appDataBasePath: base.path,
        runtimeTeamId: '00000000-0000-4000-8000-000000000001',
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

      final claudeDir = p.join(
        base.path,
        'config-profiles',
        'teams',
        '00000000-0000-4000-8000-000000000001',
        'claude',
      );
      final developerSettings = p.join(claudeDir, 'settings', 'developer.json');
      expect(env!['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(
        env[ConfigProfileService.claudeSettingsFileEnvKey],
        developerSettings,
      );

      final settingsFile = File(developerSettings);
      final settings =
          jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;
      final settingsEnv = settings['env'] as Map<String, Object?>;
      expect(
        settingsEnv['ANTHROPIC_BASE_URL'],
        'https://api.deepseek.com/anthropic',
      );
      expect(settingsEnv['ANTHROPIC_MODEL'], 'sonnet');
    },
  );

  test(
    'claude member settings use member provider over team provider',
    () async {
      Future<void> writeProvider({
        required String id,
        required String baseUrl,
        required String token,
        required String model,
      }) async {
        final providerSettings = File(
          p.join(base.path, 'providers', 'claude', id, 'settings.json'),
        );
        await providerSettings.parent.create(recursive: true);
        await providerSettings.writeAsString(
          jsonEncode({
            'env': {
              'ANTHROPIC_BASE_URL': baseUrl,
              'ANTHROPIC_AUTH_TOKEN': token,
              'ANTHROPIC_MODEL': model,
            },
          }),
        );
      }

      await writeProvider(
        id: 'deepseek',
        baseUrl: 'https://api.deepseek.com/anthropic',
        token: 'sk-deepseek',
        model: 'deepseek-default',
      );
      await writeProvider(
        id: 'moonshot',
        baseUrl: 'https://api.moonshot.example/anthropic',
        token: 'sk-moonshot',
        model: 'moonshot-default',
      );

      await TeamLaunchEnvironmentBuilder.build(
        appDataBasePath: base.path,
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
            base.path,
            'config-profiles',
            'teams',
            'team-a',
            'claude',
            'settings',
            '$memberName.json',
          ),
        );
        final settings =
            jsonDecode(await settingsFile.readAsString())
                as Map<String, Object?>;
        return settings['env'] as Map<String, Object?>;
      }

      final developerEnv = await readEnv('developer');
      expect(
        developerEnv['ANTHROPIC_BASE_URL'],
        'https://api.deepseek.com/anthropic',
      );
      expect(developerEnv['ANTHROPIC_AUTH_TOKEN'], 'sk-deepseek');
      expect(developerEnv['ANTHROPIC_MODEL'], 'sonnet');

      final reviewerEnv = await readEnv('reviewer');
      expect(
        reviewerEnv['ANTHROPIC_BASE_URL'],
        'https://api.moonshot.example/anthropic',
      );
      expect(reviewerEnv['ANTHROPIC_AUTH_TOKEN'], 'sk-moonshot');
      expect(reviewerEnv['ANTHROPIC_MODEL'], 'opus');
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
