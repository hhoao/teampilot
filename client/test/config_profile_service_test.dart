import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli_data_layout.dart';
import 'package:teampilot/services/config_profile_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

String _sessionClaudeDir(String base, String teamId, String sessionId) =>
    p.join(
      base,
      'config-profiles',
      'teams',
      teamId,
      'members',
      sessionId,
      'claude',
    );

String _appFlashskyaiDirPath(String base) =>
    p.join(base, 'config-profiles', 'flashskyai');

void main() {
  late Directory base;
  late ConfigProfileService service;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cfg_profile_');
    final fs = LocalFilesystem();
    service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: CliDataLayout(teampilotRoot: base.path, fs: fs),
    );
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('ensureTeamProfile creates bare team scope dir only', () async {
    await service.ensureTeamProfile('team-a', cli: TeamCli.flashskyai);

    final teamRoot = Directory(
      p.join(base.path, 'config-profiles', 'teams', 'team-a'),
    );
    expect(await teamRoot.exists(), isTrue);
    expect(
      await Directory(p.join(teamRoot.path, 'flashskyai')).exists(),
      isFalse,
    );
    expect(await Directory(p.join(teamRoot.path, 'members')).exists(), isFalse);
  });

  test('prepareTeamLaunch for flashskyai uses team adhoc member dir', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.flashskyai,
      workingDirectory: '/workspace/flashskyai',
    );

    final memberFlashskyaiDir = p.join(
      base.path,
      'config-profiles',
      'teams',
      'team-a',
      'members',
      configProfileAdhocSessionId,
      'flashskyai',
    );

    expect(await Directory(_appFlashskyaiDirPath(base.path)).exists(), isTrue);
    expect(await Directory(memberFlashskyaiDir).exists(), isTrue);
    expect(env.keys, ['FLASHSKYAI_CONFIG_DIR', 'LLM_CONFIG_PATH']);
    expect(env['FLASHSKYAI_CONFIG_DIR'], memberFlashskyaiDir);
    expect(
      env['LLM_CONFIG_PATH'],
      p.join(base.path, 'config-profiles', 'flashskyai', 'llm_config.json'),
    );

    final metadata = File(
      p.join(
        memberFlashskyaiDir,
        ConfigProfileService.flashskyaiMetadataFileName,
      ),
    );
    expect(await metadata.exists(), isTrue);
    final metadataJson =
        jsonDecode(await metadata.readAsString()) as Map<String, Object?>;
    final projects = metadataJson['projects'] as Map<String, Object?>;
    final projectConfig =
        projects['/workspace/flashskyai'] as Map<String, Object?>;
    expect(projectConfig['hasTrustDialogAccepted'], isTrue);

    final settings = File(
      p.join(
        memberFlashskyaiDir,
        ConfigProfileService.flashskyaiSettingsFileName,
      ),
    );
    expect(await settings.exists(), isTrue);
    final settingsJson =
        jsonDecode(await settings.readAsString()) as Map<String, Object?>;
    expect(settingsJson['skipDangerousModePermissionPrompt'], isTrue);
  });

  test('prepareTeamLaunch for codex returns CODEX_HOME only', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.codex,
    );

    final codexDir = p.join(
      base.path,
      'config-profiles',
      'teams',
      'team-a',
      'members',
      configProfileAdhocSessionId,
      'codex',
    );
    expect(env.keys, ['CODEX_HOME']);
    expect(env['CODEX_HOME'], codexDir);
    expect(File(p.join(codexDir, 'auth.json')).existsSync(), isFalse);
  });

  test('prepareTeamLaunch for claude returns env and writes roster', () async {
    const sessionId = '00000000-0000-4000-8000-000000000099';
    final env = await service.prepareTeamLaunch(
      teamId: 'Team A!',
      runtimeTeamId: sessionId,
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

    final claudeDir = _sessionClaudeDir(base.path, 'Team A!', sessionId);
    expect(env.keys, [
      'CLAUDE_CONFIG_DIR',
      'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS',
    ]);
    expect(env['CLAUDE_CONFIG_DIR'], claudeDir);

    final roster = File(
      p.join(claudeDir, 'teams', sessionId.toLowerCase(), 'config.json'),
    );
    expect(await roster.exists(), isTrue);

    final decoded =
        jsonDecode(await roster.readAsString()) as Map<String, Object?>;
    expect(decoded['name'], sessionId);
    expect(decoded['leadAgentId'], 'team-lead@$sessionId');

    final metadata =
        jsonDecode(
              await File(
                p.join(claudeDir, ConfigProfileService.claudeMetadataFileName),
              ).readAsString(),
            )
            as Map<String, Object?>;
    final projects = metadata['projects'] as Map<String, Object?>;
    final projectConfig = projects['/workspace/project'] as Map<String, Object?>;
    expect(projectConfig['hasTrustDialogAccepted'], isTrue);

    final members = decoded['members'] as List<Object?>;
    expect(members, hasLength(2));
    expect((members.first as Map)['agentId'], 'team-lead@$sessionId');
    expect((members.last as Map)['cwd'], '/workspace/project');
  });

  test(
    'prepareTeamLaunch for claude member returns runtime dir and settings file',
    () async {
      const sessionId = '00000000-0000-4000-8000-000000000001';
      final env = await service.prepareTeamLaunch(
        teamId: 'team-a',
        runtimeTeamId: sessionId,
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

      final claudeDir = _sessionClaudeDir(base.path, 'team-a', sessionId);
      final developerSettings = p.join(claudeDir, 'settings', 'developer.json');
      expect(env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(
        env[ConfigProfileService.claudeSettingsFileEnvKey],
        developerSettings,
      );

      final teamEnv =
          (jsonDecode(
                    await File(
                      p.join(claudeDir, 'settings.json'),
                    ).readAsString(),
                  )
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(teamEnv['ANTHROPIC_MODEL'], 'team-default');

      final memberEnv =
          (jsonDecode(await File(developerSettings).readAsString())
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(
        memberEnv['ANTHROPIC_BASE_URL'],
        'https://api.example.com/anthropic',
      );
      expect(memberEnv['ANTHROPIC_MODEL'], 'sonnet');
    },
  );

  test(
    'prepareTeamLaunch for claude without runtime uses adhoc session and team roster name',
    () async {
      await service.prepareTeamLaunch(
        teamId: 'team-a',
        cli: TeamCli.claude,
        members: const [TeamMemberConfig(id: 'dev', name: 'developer')],
      );

      final claudeDir = _sessionClaudeDir(
        base.path,
        'team-a',
        configProfileAdhocSessionId,
      );
      final roster = File(p.join(claudeDir, 'teams', 'team-a', 'config.json'));
      final decoded =
          jsonDecode(await roster.readAsString()) as Map<String, Object?>;
      expect(decoded['name'], 'team-a');
      expect(decoded['leadAgentId'], 'team-lead@team-a');
    },
  );

  test('prepareTeamLaunch for claude omits blank model', () async {
    await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: 'sess-1',
      cli: TeamCli.claude,
      members: const [TeamMemberConfig(id: 'dev', name: 'developer')],
    );

    final roster = File(
      p.join(
        _sessionClaudeDir(base.path, 'team-a', 'sess-1'),
        'teams',
        'sess-1',
        'config.json',
      ),
    );
    final member =
        (jsonDecode(await roster.readAsString()) as Map)['members'] as List;
    expect((member.single as Map).containsKey('model'), isFalse);
  });
}
