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
    final env = (await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.flashskyai,
      workingDirectory: '/workspace/flashskyai',
    )).environment;

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
    expect(
      env.keys,
      [
        ConfigProfileService.flashskyaiConfigDirEnvKey,
        ConfigProfileService.flashskyaiSessionHomeDirEnvKey,
        'LLM_CONFIG_PATH',
      ],
    );
    expect(
      env[ConfigProfileService.flashskyaiConfigDirEnvKey],
      memberFlashskyaiDir,
    );
    expect(
      env[ConfigProfileService.flashskyaiSessionHomeDirEnvKey],
      memberFlashskyaiDir,
    );
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
    final env = (await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.codex,
    )).environment;

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
    final env = (await service.prepareTeamLaunch(
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
    )).environment;

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
    final projectConfig =
        projects['/workspace/project'] as Map<String, Object?>;
    expect(projectConfig['hasTrustDialogAccepted'], isTrue);

    final members = decoded['members'] as List<Object?>;
    expect(members, hasLength(2));
    expect((members.first as Map)['agentId'], 'team-lead@$sessionId');
    expect((members.first as Map)['agentType'], 'team-lead');
    expect((members.first as Map)['backendType'], isNull);
    final dev = members.last as Map;
    expect(dev['agentId'], 'developer-one@$sessionId');
    expect(dev['name'], 'developer-one');
    expect(dev['agentType'], 'developer-one');
    expect(dev['backendType'], 'in-process');
    expect(dev['tmuxPaneId'], 'in-process');
    expect(dev['isActive'], true);
    expect(dev['cwd'], '/workspace/project');
    expect(decoded.containsKey('env'), isFalse);

    final inboxDir = Directory(p.join(claudeDir, 'teams', sessionId.toLowerCase(), 'inboxes'));
    expect(await inboxDir.exists(), isTrue);
    expect(
      await File(p.join(inboxDir.path, 'team-lead.json')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(inboxDir.path, 'developer-one.json')).exists(),
      isTrue,
    );
  });

  test('claude roster merge preserves createdAt across launches', () async {
    const sessionId = 'sess-merge';
    const members = [
      TeamMemberConfig(id: 'lead', name: 'team-lead', joinedAt: 100),
      TeamMemberConfig(id: 'dev', name: 'researcher', joinedAt: 200),
    ];
    await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: sessionId,
      cli: TeamCli.claude,
      members: members,
      workingDirectory: '/ws',
    );
    final rosterPath = p.join(
      _sessionClaudeDir(base.path, 'team-a', sessionId),
      'teams',
      sessionId,
      'config.json',
    );
    final first =
        jsonDecode(await File(rosterPath).readAsString()) as Map<String, Object?>;
    final createdAt = first['createdAt'];

    await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: sessionId,
      cli: TeamCli.claude,
      members: members,
      workingDirectory: '/ws',
      team: const TeamConfig(
        id: 'team-a',
        name: 'team-a',
        description: 'Research squad',
      ),
      leadSessionId: 'chat-session-uuid',
    );
    final second =
        jsonDecode(await File(rosterPath).readAsString()) as Map<String, Object?>;
    expect(second['createdAt'], createdAt);
    expect(second['description'], 'Research squad');
    expect(second['leadSessionId'], 'chat-session-uuid');
  });

  test(
    'prepareTeamLaunch for claude member returns runtime dir and settings file',
    () async {
      const sessionId = '00000000-0000-4000-8000-000000000001';
      final env = (await service.prepareTeamLaunch(
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
      )).environment;

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
    final members =
        (jsonDecode(await roster.readAsString()) as Map)['members'] as List;
    final dev = members.cast<Map>().firstWhere((m) => m['name'] == 'developer');
    expect(dev.containsKey('model'), isFalse);
  });

  test(
    'prepareTeamLaunch merges trusted projects into existing metadata',
    () async {
      const sessionId = 'sess-trust';
      final metadataPath = p.join(
        _sessionClaudeDir(base.path, 'team-a', sessionId),
        ConfigProfileService.claudeMetadataFileName,
      );
      await Directory(p.dirname(metadataPath)).create(recursive: true);
      await File(metadataPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'hasCompletedOnboarding': true,
          'customField': 'keep-me',
          'projects': {
            '/workspace/old': {
              'hasTrustDialogAccepted': true,
              'lastOpenedAt': '2024',
            },
          },
        }),
      );

      await service.prepareTeamLaunch(
        teamId: 'team-a',
        runtimeTeamId: sessionId,
        cli: TeamCli.claude,
        workingDirectory: '/workspace/new',
        additionalDirectories: const ['/workspace/extra'],
      );

      final metadata =
          jsonDecode(await File(metadataPath).readAsString())
              as Map<String, Object?>;
      expect(metadata['customField'], 'keep-me');
      final projects = metadata['projects'] as Map<String, Object?>;
      expect(projects.keys, containsAll(['/workspace/old', '/workspace/new', '/workspace/extra']));
      expect(
        (projects['/workspace/old'] as Map)['lastOpenedAt'],
        '2024',
      );
      expect(
        (projects['/workspace/new'] as Map)['hasTrustDialogAccepted'],
        isTrue,
      );
      expect(
        (projects['/workspace/new'] as Map)['projectOnboardingSeenCount'],
        1,
      );
      expect(
        (projects['/workspace/extra'] as Map)['hasTrustDialogAccepted'],
        isTrue,
      );
    },
  );

  test(
    'prepareTeamLaunch writes Windows path variants for trusted projects',
    () async {
      if (!Platform.isWindows) return;

      const sessionId = 'sess-win-trust';
      await service.prepareTeamLaunch(
        teamId: 'team-a',
        runtimeTeamId: sessionId,
        cli: TeamCli.claude,
        workingDirectory: r'C:\Users\haung\Documents',
      );

      final metadataPath = p.join(
        _sessionClaudeDir(base.path, 'team-a', sessionId),
        ConfigProfileService.claudeMetadataFileName,
      );
      final metadata =
          jsonDecode(await File(metadataPath).readAsString())
              as Map<String, Object?>;
      final projects = metadata['projects'] as Map<String, Object?>;
      expect(
        projects.keys,
        containsAll([
          p.normalize(r'C:\Users\haung\Documents'),
          'C:/Users/haung/Documents',
        ]),
      );
      final forwardSlash =
          projects['C:/Users/haung/Documents'] as Map<String, Object?>;
      expect(forwardSlash['hasTrustDialogAccepted'], isTrue);
      expect(forwardSlash['projectOnboardingSeenCount'], 1);
      expect(forwardSlash['allowedTools'], isA<List<Object?>>());
      expect(forwardSlash['mcpServers'], isA<Map<String, Object?>>());
    },
  );
}
