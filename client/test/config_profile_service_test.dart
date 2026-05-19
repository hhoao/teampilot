import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/config_profile_service.dart';

void main() {
  late Directory base;
  late ConfigProfileService service;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cfg_profile_');
    service = ConfigProfileService(basePath: base.path);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test(
    'ensureTeamProfile for flashskyai creates flashskyai dir and metadata only',
    () async {
      await service.ensureTeamProfile('team-a', cli: TeamCli.flashskyai);

      final teamRoot = Directory(
        p.join(base.path, 'config-profiles', 'teams', 'team-a'),
      );
      expect(await teamRoot.exists(), isTrue);
      expect(
        await Directory(p.join(teamRoot.path, 'flashskyai')).exists(),
        isTrue,
      );
      expect(await Directory(p.join(teamRoot.path, 'codex')).exists(), isFalse);
      expect(
        await Directory(p.join(teamRoot.path, 'claude')).exists(),
        isFalse,
      );

      final metadata = File(
        p.join(
          teamRoot.path,
          'flashskyai',
          ConfigProfileService.flashskyaiMetadataFileName,
        ),
      );
      expect(await metadata.exists(), isTrue);
      final decoded =
          jsonDecode(await metadata.readAsString()) as Map<String, Object?>;
      expect(decoded['hasCompletedOnboarding'], isTrue);
    },
  );

  test('ensureTeamProfile for codex creates codex dir only', () async {
    await service.ensureTeamProfile('team-a', cli: TeamCli.codex);

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
    expect(await Directory(p.join(teamRoot, 'codex')).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isFalse);
  });

  test(
    'ensureTeamProfile for claude creates claude dir and metadata only',
    () async {
      await service.ensureTeamProfile('team-a', cli: TeamCli.claude);

      final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
      expect(await Directory(p.join(teamRoot, 'claude')).exists(), isTrue);
      expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isFalse);
      expect(await Directory(p.join(teamRoot, 'codex')).exists(), isFalse);

      final metadata = File(p.join(teamRoot, 'claude', '.claude.json'));
      expect(await metadata.exists(), isTrue);
      final decoded =
          jsonDecode(await metadata.readAsString()) as Map<String, Object?>;
      expect(decoded, {'hasCompletedOnboarding': true});
    },
  );

  test('does not overwrite existing team flashskyai metadata', () async {
    final metadata = File(
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'flashskyai',
        ConfigProfileService.flashskyaiMetadataFileName,
      ),
    );
    await metadata.parent.create(recursive: true);
    await metadata.writeAsString('{"hasCompletedOnboarding":false}');

    await service.ensureTeamProfile('team-a', cli: TeamCli.flashskyai);

    expect(await metadata.readAsString(), '{"hasCompletedOnboarding":false}');
  });

  test('does not overwrite existing team claude metadata', () async {
    final metadata = File(
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'claude',
        '.claude.json',
      ),
    );
    await metadata.parent.create(recursive: true);
    await metadata.writeAsString('{"hasCompletedOnboarding":false}');

    await service.ensureTeamProfile('team-a', cli: TeamCli.claude);

    expect(await metadata.readAsString(), '{"hasCompletedOnboarding":false}');
  });

  test(
    'prepareTeamLaunch for flashskyai returns flashskyai env only',
    () async {
      final env = await service.prepareTeamLaunch(
        teamId: 'team-a',
        cli: TeamCli.flashskyai,
      );

      final commonFlashDir = p.join(
        base.path,
        'config-profiles',
        'common',
        'flashskyai',
      );
      final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');

      expect(await Directory(commonFlashDir).exists(), isTrue);
      expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isTrue);
      expect(await Directory(p.join(teamRoot, 'codex')).exists(), isFalse);
      expect(env.keys, ['FLASHSKYAI_CONFIG_DIR', 'LLM_CONFIG_PATH']);
      expect(env['FLASHSKYAI_CONFIG_DIR'], p.join(teamRoot, 'flashskyai'));
      expect(env['LLM_CONFIG_PATH'], p.join(commonFlashDir, 'llm_config.json'));

      final metadata = File(
        p.join(
          teamRoot,
          'flashskyai',
          ConfigProfileService.flashskyaiMetadataFileName,
        ),
      );
      expect(await metadata.exists(), isTrue);
    },
  );

  test('prepareTeamLaunch for codex returns CODEX_HOME only', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.codex,
    );

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
    expect(env.keys, ['CODEX_HOME']);
    expect(env['CODEX_HOME'], p.join(teamRoot, 'codex'));
    expect(File(p.join(env['CODEX_HOME']!, 'auth.json')).existsSync(), isFalse);
  });

  test('prepareTeamLaunch for claude returns env and writes roster', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'Team A!',
      cli: TeamCli.claude,
      members: const [
        TeamMemberConfig(
          id: 'lead',
          name: 'team-lead',
          model: 'opus',
          joinedAt: 100,
        ),
        TeamMemberConfig(
          id: 'dev',
          name: 'Developer One',
          model: 'sonnet',
          joinedAt: 200,
        ),
      ],
      workingDirectory: '/workspace/project',
    );

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'Team A!');
    final claudeDir = p.join(teamRoot, 'claude');
    expect(env.keys, [
      'CLAUDE_CONFIG_DIR',
      'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS',
    ]);
    expect(env['CLAUDE_CONFIG_DIR'], claudeDir);
    expect(env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');

    final roster = File(p.join(claudeDir, 'teams', 'team-a-', 'config.json'));
    expect(await roster.exists(), isTrue);

    final decoded =
        jsonDecode(await roster.readAsString()) as Map<String, Object?>;
    expect(decoded['name'], 'Team A!');
    expect(decoded['createdAt'], isA<int>());
    expect(decoded['leadAgentId'], 'team-lead@Team A!');
    expect(decoded['env'], {'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1'});

    final members = decoded['members'] as List<Object?>;
    expect(members, hasLength(2));
    expect(members.first, {
      'agentId': 'team-lead@Team A!',
      'name': 'team-lead',
      'joinedAt': 100,
      'tmuxPaneId': '',
      'cwd': '/workspace/project',
      'subscriptions': <Object?>[],
      'model': 'opus',
      'agentType': 'team-lead',
    });
    expect(members.last, {
      'agentId': 'Developer One@Team A!',
      'name': 'Developer One',
      'joinedAt': 200,
      'tmuxPaneId': '',
      'cwd': '/workspace/project',
      'subscriptions': <Object?>[],
      'model': 'sonnet',
    });
  });

  test(
    'prepareTeamLaunch for claude member returns runtime dir and settings file',
    () async {
      final env = await service.prepareTeamLaunch(
        teamId: 'team-a',
        runtimeTeamId: 'team-a-session-0',
        cli: TeamCli.claude,
        members: const [
          TeamMemberConfig(id: 'lead', name: 'team-lead', model: 'opus'),
          TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
        ],
        member: const TeamMemberConfig(
          id: 'dev',
          name: 'developer',
          model: 'sonnet',
        ),
        claudeSettings: const {
          'env': {
            'ANTHROPIC_BASE_URL': 'https://api.example.com/anthropic',
            'ANTHROPIC_MODEL': 'team-default',
          },
        },
      );

      final claudeDir = p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a-session-0',
        'claude',
      );
      final developerSettings = p.join(claudeDir, 'settings', 'developer.json');
      expect(env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');
      expect(
        env[ConfigProfileService.claudeSettingsFileEnvKey],
        developerSettings,
      );

      final teamSettings =
          jsonDecode(
                await File(p.join(claudeDir, 'settings.json')).readAsString(),
              )
              as Map<String, Object?>;
      final teamEnv = teamSettings['env'] as Map<String, Object?>;
      expect(teamEnv['ANTHROPIC_MODEL'], 'team-default');

      final memberSettings =
          jsonDecode(await File(developerSettings).readAsString())
              as Map<String, Object?>;
      final memberEnv = memberSettings['env'] as Map<String, Object?>;
      expect(
        memberEnv['ANTHROPIC_BASE_URL'],
        'https://api.example.com/anthropic',
      );
      expect(memberEnv['ANTHROPIC_MODEL'], 'sonnet');
      expect(memberEnv['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'sonnet');
      expect(memberEnv['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'sonnet');
      expect(memberEnv['ANTHROPIC_DEFAULT_OPUS_MODEL'], 'sonnet');
      expect(memberEnv['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');
      expect(await Directory(p.join(claudeDir, 'members')).exists(), isFalse);
    },
  );

  test(
    'prepareTeamLaunch for claude preserves existing roster fields',
    () async {
      final roster = File(
        p.join(
          base.path,
          'config-profiles',
          'teams',
          'team-a',
          'claude',
          'teams',
          'team-a',
          'config.json',
        ),
      );
      await roster.parent.create(recursive: true);
      await roster.writeAsString(
        jsonEncode({
          'name': 'Old Name',
          'createdAt': 1234,
          'leadAgentId': 'old-lead',
          'customTop': 'keep',
          'env': {
            'ANTHROPIC_BASE_URL': 'https://proxy.example.com',
            'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '0',
          },
          'members': [
            {
              'agentId': 'developer@team-a',
              'name': 'developer',
              'joinedAt': 5678,
              'sessionId': 'session-1',
              'isActive': true,
              'cwd': '/old/cwd',
              'subscriptions': ['team-lead@team-a'],
              'customMember': 'also keep',
            },
          ],
        }),
      );

      await service.prepareTeamLaunch(
        teamId: 'team-a',
        cli: TeamCli.claude,
        members: const [
          TeamMemberConfig(id: 'dev', name: 'developer', model: 'haiku'),
        ],
        workingDirectory: '/new/cwd',
      );

      final decoded =
          jsonDecode(await roster.readAsString()) as Map<String, Object?>;
      expect(decoded['name'], 'team-a');
      expect(decoded['createdAt'], 1234);
      expect(decoded['leadAgentId'], 'team-lead@team-a');
      expect(decoded['customTop'], 'keep');
      expect(decoded['env'], {
        'ANTHROPIC_BASE_URL': 'https://proxy.example.com',
        'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      });

      final members = decoded['members'] as List<Object?>;
      expect(members, hasLength(1));
      final member = members.single as Map<String, Object?>;
      expect(member['agentId'], 'developer@team-a');
      expect(member['name'], 'developer');
      expect(member['joinedAt'], 5678);
      expect(member['sessionId'], 'session-1');
      expect(member['isActive'], true);
      expect(member['cwd'], '/old/cwd');
      expect(member['subscriptions'], <Object?>[]);
      expect(member['customMember'], 'also keep');
      expect(member['model'], 'haiku');
      expect(member.containsKey('agentType'), isFalse);
    },
  );

  test('prepareTeamLaunch for claude omits blank model', () async {
    await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.claude,
      members: const [TeamMemberConfig(id: 'dev', name: 'developer')],
    );

    final roster = File(
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'claude',
        'teams',
        'team-a',
        'config.json',
      ),
    );
    final decoded =
        jsonDecode(await roster.readAsString()) as Map<String, Object?>;
    final members = decoded['members'] as List<Object?>;
    final member = members.single as Map<String, Object?>;
    expect(member.containsKey('model'), isFalse);
  });

  test(
    'prepareTeamLaunch for claude with no members writes empty roster',
    () async {
      final env = await service.prepareTeamLaunch(
        teamId: 'team-a',
        cli: TeamCli.claude,
      );

      final roster = File(
        p.join(
          base.path,
          'config-profiles',
          'teams',
          'team-a',
          'claude',
          'teams',
          'team-a',
          'config.json',
        ),
      );
      final decoded =
          jsonDecode(await roster.readAsString()) as Map<String, Object?>;
      expect(decoded['members'], isEmpty);
      expect(decoded['leadAgentId'], 'team-lead@team-a');
      expect(
        env['CLAUDE_CONFIG_DIR'],
        p.join(base.path, 'config-profiles', 'teams', 'team-a', 'claude'),
      );
    },
  );
}
