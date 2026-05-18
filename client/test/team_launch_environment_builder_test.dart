import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
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
        tempTeamRegistryPath: p.join(remoteRoot, 'ui-temp-teams.json'),
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

  test('empty team id keeps legacy llm override fallback', () async {
    final env = await TeamLaunchEnvironmentBuilder.build(
      appDataBasePath: base.path,
      team: const TeamConfig(id: '', name: ''),
      llmConfigPathOverride: '/global/llm_config.json',
    );

    expect(env, {'LLM_CONFIG_PATH': '/global/llm_config.json'});
  });
}
