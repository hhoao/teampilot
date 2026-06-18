import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/script_file_hook_provisioner.dart';
import 'package:teampilot/services/host/team_pilot_hook_scripts.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
import 'package:teampilot/services/team/team_lead_delegate_settings_merge.dart';
import 'package:teampilot/services/team/team_lead_settings_merge.dart';

Future<void> _seedClaudeProvider(
  String basePath, {
  required String id,
  required Map<String, Object?> env,
}) async {
  final repository = AppProviderRepository(basePath: basePath);
  await repository.saveProviders(CliTool.claude, [
    AppProviderConfig(
      id: id,
      cli: CliTool.claude,
      name: id,
      category: AppProviderCategory.thirdParty,
      config: {'env': env},
    ),
  ]);
}

Future<void> _seedCodexProvider(
  String basePath, {
  required String id,
  required String configToml,
  String apiKey = 'sk-codex',
  Map<String, Object?> meta = const {},
}) async {
  final repository = AppProviderRepository(basePath: basePath);
  await repository.saveProviders(CliTool.codex, [
    AppProviderConfig(
      id: id,
      cli: CliTool.codex,
      name: id,
      apiKey: apiKey,
      baseUrl: 'http://127.0.0.1:15721/v1',
      defaultModel: 'deepseek-v4-flash',
      category: AppProviderCategory.thirdParty,
      config: {
        'auth': {'OPENAI_API_KEY': apiKey},
        'configToml': configToml,
        if (meta.isNotEmpty) 'meta': meta,
      },
    ),
  ]);
}

const _testWorkspaceId = 'workspace-1';

String _sessionToolDir(
  String base,
  String sessionId,
  String tool, {
  String? memberId,
}) {
  final root = p.join(
    base,
    'workspace',
    'workspaces',
    _testWorkspaceId,
    'sessions',
    sessionId,
    'runtime',
  );
  if (memberId != null && memberId.isNotEmpty) {
    return p.join(root, memberId, tool);
  }
  return p.join(root, tool);
}

String _sessionClaudeDir(String base, String sessionId, {String? memberId}) =>
    _sessionToolDir(base, sessionId, 'claude', memberId: memberId);

String _sessionFlashskyaiDir(String base, String sessionId, {String? memberId}) =>
    _sessionToolDir(base, sessionId, 'flashskyai', memberId: memberId);

String _rosterDirName(String cliTeamName) =>
    ClaudeTeamRosterService.safeClaudePathSegment(cliTeamName);

String _appFlashskyaiDirPath(String base) =>
    p.join(base, 'cli-defaults', 'flashskyai');


void main() {
  late Directory base;
  late ConfigProfileService service;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cfg_profile_');
    final fs = LocalFilesystem();
    service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      hostEnvironment: HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      ),
      teamLeadHookProvisioner: ScriptFileHookProvisioner(
        fs: fs,
        runner: HostExecutionEnvironment.resolve(
          isWindowsHost: false,
          storageMode: StorageBackendMode.native,
        ).scriptRunner,
        baseFileName: TeamPilotHookScripts.teamLeadSelf,
        loadScript: (_) async =>
            '#!/usr/bin/env bash\n# teampilot-deny-team-lead-self-message\n',
      ),
      teamLeadDelegateHookProvisioner: ScriptFileHookProvisioner(
        fs: fs,
        runner: HostExecutionEnvironment.resolve(
          isWindowsHost: false,
          storageMode: StorageBackendMode.native,
        ).scriptRunner,
        baseFileName: TeamPilotHookScripts.teamLeadDelegate,
        loadScript: (_) async =>
            '#!/usr/bin/env bash\n# teampilot-team-lead-delegate-only\n',
      ),
    );
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('ensureTeamProfile creates bare team scope dir only', () async {
    await service.ensureTeamProfile('team-a', cli: CliTool.flashskyai);

    final teamRoot = Directory(
      p.join(base.path, 'identities-runtime', 'team-a'),
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
      workspaceId: _testWorkspaceId,
      sessionId: configProfileAdhocSessionId,
      teamId: 'team-a',
      cliTeamName: 'team-a',
      cli: CliTool.flashskyai,
      workingDirectory: '/workspace/flashskyai',
    )).environment;

    final memberFlashskyaiDir = _sessionFlashskyaiDir(
      base.path,
      configProfileAdhocSessionId,
    );

    expect(await Directory(_appFlashskyaiDirPath(base.path)).exists(), isTrue);
    expect(await Directory(memberFlashskyaiDir).exists(), isTrue);
    expect(
      env.keys,
      [
        FlashskyaiConfigProfileCapability.configDirEnvKey,
        FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey,
        'LLM_CONFIG_PATH',
        'FLASHSKYAI_CODE_NO_FLICKER',
      ],
    );
    expect(env['FLASHSKYAI_CODE_NO_FLICKER'], '1');
    expect(
      env[FlashskyaiConfigProfileCapability.configDirEnvKey],
      memberFlashskyaiDir,
    );
    expect(
      env[FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey],
      memberFlashskyaiDir,
    );
    expect(
      env['LLM_CONFIG_PATH'],
      p.join(base.path, 'cli-defaults', 'flashskyai', 'llm_config.json'),
    );

    final metadata = File(
      p.join(
        memberFlashskyaiDir,
        FlashskyaiConfigProfileCapability.metadataFileName,
      ),
    );
    expect(await metadata.exists(), isTrue);
    final metadataJson =
        jsonDecode(await metadata.readAsString()) as Map<String, Object?>;
    final workspaces = metadataJson['workspaces'] as Map<String, Object?>;
    final workspaceConfig =
        workspaces['/workspace/flashskyai'] as Map<String, Object?>;
    expect(workspaceConfig['hasTrustDialogAccepted'], isTrue);

    final settings = File(
      p.join(
        memberFlashskyaiDir,
        FlashskyaiConfigProfileCapability.settingsFileName,
      ),
    );
    expect(await settings.exists(), isTrue);
    final settingsJson =
        jsonDecode(await settings.readAsString()) as Map<String, Object?>;
    expect(settingsJson['skipDangerousModePermissionPrompt'], isTrue);
  });

  test('prepareTeamLaunch provisions codex provider auth and config', () async {
    const providerToml = '''
model_provider = "custom"
model = "deepseek-v4-flash"

[model_providers.custom]
base_url = "http://127.0.0.1:15721/v1"
wire_api = "responses"
requires_openai_auth = true
''';
    await _seedCodexProvider(
      base.path,
      id: 'deepseek',
      configToml: providerToml,
      meta: {'proxyTakeover': true},
    );

    final outcome = await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: configProfileAdhocSessionId,
      teamId: 'team-a',
      cli: CliTool.codex,
      team: TeamProfile(
        id: 'team-a',
        name: 'team-a',
        cli: CliTool.codex,
        providerIdsByTool: const {'codex': 'deepseek'},
        members: const [
          TeamMemberConfig(id: 'worker', name: 'worker', provider: 'deepseek'),
        ],
      ),
      member: const TeamMemberConfig(
        id: 'worker',
        name: 'worker',
        provider: 'deepseek',
      ),
    );

    final codexDir = _sessionToolDir(
      base.path,
      configProfileAdhocSessionId,
      'codex',
    );
    expect(outcome.environment['CODEX_HOME'], codexDir);
    expect(outcome.warnings, isEmpty);

    final auth =
        jsonDecode(
              await File(p.join(codexDir, 'auth.json')).readAsString(),
            )
            as Map<String, Object?>;
    expect(auth['OPENAI_API_KEY'], 'PROXY_MANAGED');

    final toml = await File(p.join(codexDir, 'config.toml')).readAsString();
    expect(toml, contains('127.0.0.1:15721'));
    expect(toml, contains('deepseek-v4-flash'));
  });

  test(
    'prepareTeamLaunch merges team-bus overlay into codex config for mixed teams',
    () async {
      const providerToml = '''
model_provider = "custom"
model = "gpt-test"

[model_providers.custom]
base_url = "https://api.example.com/v1"
''';
      await _seedCodexProvider(base.path, id: 'p1', configToml: providerToml);

      await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
        sessionId: 'sess-mixed-codex',
        teamId: 'team-a',
        cliTeamName: 'sess-mixed-codex',
        cli: CliTool.codex,
        team: TeamProfile(
          id: 'team-a',
          name: 'team-a',
          cli: CliTool.codex,
          teamMode: TeamMode.mixed,
          providerIdsByTool: const {'codex': 'p1'},
          members: const [
            TeamMemberConfig(id: 'worker', name: 'worker', provider: 'p1'),
          ],
        ),
        member: const TeamMemberConfig(
          id: 'worker',
          name: 'worker',
          provider: 'p1',
        ),
        busIdleUrl: 'http://127.0.0.1:59999/idle',
      );

      final codexDir = _sessionToolDir(
        base.path,
        'sess-mixed-codex',
        'codex',
        memberId: 'worker',
      );
      final toml = await File(p.join(codexDir, 'config.toml')).readAsString();
      expect(toml, contains('https://api.example.com/v1'));
      expect(toml, contains('[mcp_servers.teammate-bus]'));
      expect(toml, contains('http://127.0.0.1:59999/mcp'));
    },
  );

  test('prepareTeamLaunch writes role prompt and injects append env', () async {
    const sessionId = 'sess-role-prompt';
    const lead = TeamMemberConfig(
      id: 'team-lead',
      name: 'team-lead',
      prompt: 'Coordinate only; delegate implementation.',
    );
    final env = (await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: const [lead],
      member: lead,
      workingDirectory: '/workspace',
    )).environment;

    final claudeDir = _sessionClaudeDir(base.path, sessionId);
    final roleFile = p.join(
      claudeDir,
      'prompts',
      'team-lead',
      'role.md',
    );
    expect(await File(roleFile).exists(), isTrue);
    expect(await File(roleFile).readAsString(), contains('Coordinate only'));

    final appendPath =
        env[MemberRoleProvision.appendSystemPromptFileEnvKey];
    expect(appendPath, roleFile);

    final settingsPath = env[ClaudeConfigProfileCapability.settingsFileEnvKey]!;
    final settings =
        jsonDecode(await File(settingsPath).readAsString())
            as Map<String, Object?>;
    final deny =
        (settings['permissions'] as Map)['deny'] as List;
    expect(deny, contains('TeamCreate'));
    expect(deny, isNot(contains('Bash')));
    expect(deny, isNot(contains('Edit')));

    final hookPath = p.join(
      claudeDir,
      'hooks',
      '${TeamPilotHookScripts.teamLeadSelf}.sh',
    );
    expect(await File(hookPath).exists(), isTrue);

    final pre = (settings['hooks'] as Map)['PreToolUse'] as List;
    for (final matcher in TeamLeadSettingsMerge.guardedTools) {
      final entry = pre.cast<Map>().firstWhere(
        (e) => e['matcher'] == matcher,
      );
      final command =
          ((entry['hooks'] as List).first as Map)['command'] as String;
      expect(command, contains('${TeamPilotHookScripts.teamLeadSelf}.sh'));
    }
  });

  test('prepareTeamLaunch adds delegate-only hook when team flag is on', () async {
    const sessionId = 'sess-delegate-only';
    const lead = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
    const team = TeamProfile(
      id: 'team-a',
      name: 'agent',
      cli: CliTool.claude,
      forceTeamLeadDelegateMode: true,
    );
    final env = (await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: team.id,
      cliTeamName: sessionId,
      cli: team.cli,
      members: const [lead],
      member: lead,
      team: team,
    )).environment;

    final claudeDir = _sessionClaudeDir(base.path, sessionId);
    final roleText = await File(
      p.join(claudeDir, 'prompts', 'team-lead', 'role.md'),
    ).readAsString();
    expect(roleText, contains('Delegate-only mode'));

    final settingsPath = env[ClaudeConfigProfileCapability.settingsFileEnvKey]!;
    final settings =
        jsonDecode(await File(settingsPath).readAsString())
            as Map<String, Object?>;
    final pre = (settings['hooks'] as Map)['PreToolUse'] as List;
    final delegateEntry = pre.cast<Map>().firstWhere(
      (e) =>
          (e['matcher'] as String?) ==
          TeamLeadDelegateSettingsMerge.blockedToolsMatcher,
    );
    final command =
        ((delegateEntry['hooks'] as List).first as Map)['command'] as String;
    expect(command, contains('${TeamPilotHookScripts.teamLeadDelegate}.sh'));

    expect(
      await File(
        p.join(
          claudeDir,
          'hooks',
          '${TeamPilotHookScripts.teamLeadDelegate}.sh',
        ),
      ).exists(),
      isTrue,
    );
  });

  test('prepareTeamLaunch flashskyai writes role prompt and append env', () async {
    const sessionId = 'sess-fs-role';
    const lead = TeamMemberConfig(
      id: 'team-lead',
      name: 'team-lead',
      prompt: 'Coordinate flashskyai teammates.',
    );
    final env = (await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.flashskyai,
      members: const [lead],
      member: lead,
      workingDirectory: '/workspace',
    )).environment;

    final flashskyaiDir = _sessionFlashskyaiDir(base.path, sessionId);
    final roleFile = p.join(flashskyaiDir, 'prompts', 'team-lead', 'role.md');
    expect(await File(roleFile).exists(), isTrue);
    expect(
      await File(roleFile).readAsString(),
      contains('Coordinate flashskyai'),
    );
    expect(
      env[MemberRoleProvision.appendSystemPromptFileEnvKey],
      roleFile,
    );

    final settings =
        jsonDecode(
              await File(
                p.join(
                  flashskyaiDir,
                  FlashskyaiConfigProfileCapability.settingsFileName,
                ),
              ).readAsString(),
            )
            as Map<String, Object?>;
    final deny = (settings['permissions'] as Map)['deny'] as List;
    expect(deny, contains('TeamCreate'));

    final hookPath = p.join(
      flashskyaiDir,
      'hooks',
      '${TeamPilotHookScripts.teamLeadSelf}.sh',
    );
    expect(await File(hookPath).exists(), isTrue);
    final pre = (settings['hooks'] as Map)['PreToolUse'] as List;
    for (final matcher in TeamLeadSettingsMerge.guardedTools) {
      final entry = pre.cast<Map>().firstWhere(
        (e) => e['matcher'] == matcher,
      );
      final command =
          ((entry['hooks'] as List).first as Map)['command'] as String;
      expect(command, contains('${TeamPilotHookScripts.teamLeadSelf}.sh'));
    }
  });

  test(
    'prepareTeamLaunch flashskyai adds delegate-only hook when team flag is on',
    () async {
      const sessionId = 'sess-fs-delegate';
      const lead = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.flashskyai,
        forceTeamLeadDelegateMode: true,
      );
      await service.prepareTeamLaunch(
        workspaceId: _testWorkspaceId,
        sessionId: sessionId,
        teamId: team.id,
        cliTeamName: sessionId,
        cli: team.cli,
        members: const [lead],
        member: lead,
        team: team,
      );

      final flashskyaiDir =
          _sessionFlashskyaiDir(base.path, sessionId);
      final roleText = await File(
        p.join(flashskyaiDir, 'prompts', 'team-lead', 'role.md'),
      ).readAsString();
      expect(roleText, contains('Delegate-only mode'));

      final settings =
          jsonDecode(
                await File(
                  p.join(
                    flashskyaiDir,
                    FlashskyaiConfigProfileCapability.settingsFileName,
                  ),
                ).readAsString(),
              )
              as Map<String, Object?>;
      final pre = (settings['hooks'] as Map)['PreToolUse'] as List;
      final delegateEntry = pre.cast<Map>().firstWhere(
        (e) =>
            (e['matcher'] as String?) ==
            TeamLeadDelegateSettingsMerge.blockedToolsMatcher,
      );
      final command =
          ((delegateEntry['hooks'] as List).first as Map)['command'] as String;
      expect(command, contains('${TeamPilotHookScripts.teamLeadDelegate}.sh'));
    },
  );

  test('team-lead SendMessage hook is not added for non-lead members', () async {
    const sessionId = 'sess-dev-only-hook';
    const dev = TeamMemberConfig(id: 'developer', name: 'developer');
    await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        dev,
      ],
      member: dev,
    );

    final claudeDir = _sessionClaudeDir(base.path, sessionId);
    final devSettingsPath = p.join(claudeDir, 'settings', 'developer.json');
    final settings =
        jsonDecode(await File(devSettingsPath).readAsString())
            as Map<String, Object?>;
    final devDeny =
        (settings['permissions'] as Map?)?['deny'] as List? ?? const [];
    expect(devDeny, contains('TeamCreate'));
    expect(settings['hooks'], isNull);

    final leadSettingsPath = p.join(claudeDir, 'settings', 'team-lead.json');
    final leadSettings =
        jsonDecode(await File(leadSettingsPath).readAsString())
            as Map<String, Object?>;
    final pre = (leadSettings['hooks'] as Map)['PreToolUse'] as List;
    expect(
      pre.cast<Map>().any((entry) => entry['matcher'] == 'SendMessage'),
      isTrue,
    );
  });

  test('prepareTeamLaunch for claude returns env and writes roster', () async {
    const sessionId = '00000000-0000-4000-8000-000000000099';
    final env = (await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: const [
        TeamMemberConfig(
          id: 'team-lead',
          name: 'Team Lead',
          model: 'opus',
          joinedAt: 100,
        ),
        TeamMemberConfig(
          id: 'developer-one',
          name: 'Developer One',
          model: 'sonnet',
          joinedAt: 200,
        ),
      ],
      workingDirectory: '/workspace/workspace',
    )).environment;

    final claudeDir = _sessionClaudeDir(base.path, sessionId);
    expect(env.keys, [
      'CLAUDE_CONFIG_DIR',
      'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS',
      'CLAUDE_CODE_NO_FLICKER',
      'MCP_TOOL_TIMEOUT',
    ]);
    expect(env['CLAUDE_CONFIG_DIR'], claudeDir);
    expect(env['MCP_TOOL_TIMEOUT'], '86400000');

    final roster = File(
      p.join(claudeDir, 'teams', _rosterDirName(sessionId), 'config.json'),
    );
    expect(await roster.exists(), isTrue);

    final decoded =
        jsonDecode(await roster.readAsString()) as Map<String, Object?>;
    expect(decoded['name'], sessionId);
    expect(decoded['leadAgentId'], 'team-lead');

    final metadata =
        jsonDecode(
              await File(
                p.join(claudeDir, ClaudeConfigProfileCapability.metadataFileName),
              ).readAsString(),
            )
            as Map<String, Object?>;
    final workspaces = metadata['workspaces'] as Map<String, Object?>;
    final workspaceConfig =
        workspaces['/workspace/workspace'] as Map<String, Object?>;
    expect(workspaceConfig['hasTrustDialogAccepted'], isTrue);
    expect(workspaceConfig['hasClaudeMdExternalIncludesApproved'], isTrue);
    expect(workspaceConfig['hasClaudeMdExternalIncludesWarningShown'], isTrue);

    final members = decoded['members'] as List<Object?>;
    expect(members, hasLength(2));
    expect((members.first as Map)['agentId'], 'team-lead');
    expect((members.first as Map)['agentType'], 'team-lead');
    expect((members.first as Map)['backendType'], isNull);
    final dev = members.last as Map;
    expect(dev['agentId'], 'developer-one@$sessionId');
    expect(dev['name'], 'developer-one');
    expect(dev['agentType'], 'developer-one');
    expect(dev['backendType'], 'in-process');
    expect(dev['tmuxPaneId'], 'in-process');
    expect(dev.containsKey('isActive'), isFalse);
    expect(dev['cwd'], '/workspace/workspace');
    expect(decoded.containsKey('env'), isFalse);

    final inboxDir = Directory(
      p.join(claudeDir, 'teams', _rosterDirName(sessionId), 'inboxes'),
    );
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
      TeamMemberConfig(id: 'team-lead', name: 'team-lead', joinedAt: 100),
      TeamMemberConfig(id: 'developer', name: 'researcher', joinedAt: 200),
    ];
    await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: members,
      workingDirectory: '/ws',
    );
    final rosterPath = p.join(
      _sessionClaudeDir(base.path, sessionId),
      'teams',
      _rosterDirName(sessionId),
      'config.json',
    );
    final first =
        jsonDecode(await File(rosterPath).readAsString()) as Map<String, Object?>;
    final createdAt = first['createdAt'];

    await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: members,
      workingDirectory: '/ws',
      team: const TeamProfile(
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
      await _seedClaudeProvider(
        base.path,
        id: 'custom',
        env: const {
          'ANTHROPIC_BASE_URL': 'https://api.example.com/anthropic',
          'ANTHROPIC_MODEL': 'team-default',
        },
      );
      final env = (await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
        cli: CliTool.claude,
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead', model: 'opus'),
          TeamMemberConfig(id: 'developer', name: 'developer', model: 'sonnet'),
        ],
        member: const TeamMemberConfig(
          id: 'developer',
          name: 'developer',
          model: 'sonnet',
        ),
        team: TeamProfile(
          id: 'team-a',
          name: 'team-a',
          cli: CliTool.claude,
          providerIdsByTool: const {'claude': 'custom'},
        ),
      )).environment;

      final claudeDir = _sessionClaudeDir(base.path, sessionId);
      final developerSettings = p.join(claudeDir, 'settings', 'developer.json');
      expect(env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(
        env[ClaudeConfigProfileCapability.settingsFileEnvKey],
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
      workspaceId: _testWorkspaceId,
      sessionId: configProfileAdhocSessionId,
      teamId: 'team-a',
        cli: CliTool.claude,
        members: const [TeamMemberConfig(id: 'developer', name: 'developer')],
      );

      final claudeDir = _sessionClaudeDir(
        base.path,
        configProfileAdhocSessionId,
      );
      final roster = File(p.join(claudeDir, 'teams', 'team-a', 'config.json'));
      final decoded =
          jsonDecode(await roster.readAsString()) as Map<String, Object?>;
      expect(decoded['name'], 'team-a');
      expect(decoded['leadAgentId'], 'team-lead');
    },
  );

  test('prepareTeamLaunch for claude omits blank model', () async {
    await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: 'sess-1',
      teamId: 'team-a',
      cliTeamName: 'sess-1',
      cli: CliTool.claude,
      members: const [TeamMemberConfig(id: 'developer', name: 'developer')],
    );

    final roster = File(
      p.join(
        _sessionClaudeDir(base.path, 'sess-1'),
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
    'prepareTeamLaunch merges trusted workspaces into existing metadata',
    () async {
      const sessionId = 'sess-trust';
      final metadataPath = p.join(
        _sessionClaudeDir(base.path, sessionId),
        ClaudeConfigProfileCapability.metadataFileName,
      );
      await Directory(p.dirname(metadataPath)).create(recursive: true);
      await File(metadataPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'hasCompletedOnboarding': true,
          'customField': 'keep-me',
          'workspaces': {
            '/workspace/old': {
              'hasTrustDialogAccepted': true,
              'lastOpenedAt': '2024',
            },
          },
        }),
      );

      await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
        cli: CliTool.claude,
        workingDirectory: '/workspace/new',
        additionalDirectories: const ['/workspace/extra'],
      );

      final metadata =
          jsonDecode(await File(metadataPath).readAsString())
              as Map<String, Object?>;
      expect(metadata['customField'], 'keep-me');
      final workspaces = metadata['workspaces'] as Map<String, Object?>;
      expect(workspaces.keys, containsAll(['/workspace/old', '/workspace/new', '/workspace/extra']));
      expect(
        (workspaces['/workspace/old'] as Map)['lastOpenedAt'],
        '2024',
      );
      expect(
        (workspaces['/workspace/new'] as Map)['hasTrustDialogAccepted'],
        isTrue,
      );
      expect(
        (workspaces['/workspace/new'] as Map)['workspaceOnboardingSeenCount'],
        1,
      );
      expect(
        (workspaces['/workspace/extra'] as Map)['hasTrustDialogAccepted'],
        isTrue,
      );
      expect(
        (workspaces['/workspace/new'] as Map)['hasClaudeMdExternalIncludesApproved'],
        isTrue,
      );
      expect(
        (workspaces['/workspace/new'] as Map)['hasClaudeMdExternalIncludesWarningShown'],
        isTrue,
      );
    },
  );

  test(
    'prepareTeamLaunch writes Windows path variants for trusted workspaces',
    () async {
      if (!Platform.isWindows) return;

      const sessionId = 'sess-win-trust';
      await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
        cli: CliTool.claude,
        workingDirectory: r'C:\Users\haung\Documents',
      );

      final metadataPath = p.join(
        _sessionClaudeDir(base.path, sessionId),
        ClaudeConfigProfileCapability.metadataFileName,
      );
      final metadata =
          jsonDecode(await File(metadataPath).readAsString())
              as Map<String, Object?>;
      final workspaces = metadata['workspaces'] as Map<String, Object?>;
      expect(
        workspaces.keys,
        containsAll([
          p.normalize(r'C:\Users\haung\Documents'),
          'C:/Users/haung/Documents',
          '/mnt/c/Users/haung/Documents',
        ]),
      );
      final forwardSlash =
          workspaces['C:/Users/haung/Documents'] as Map<String, Object?>;
      expect(forwardSlash['hasTrustDialogAccepted'], isTrue);
      expect(forwardSlash['workspaceOnboardingSeenCount'], 1);
      expect(forwardSlash['allowedTools'], isA<List<Object?>>());
      expect(forwardSlash['mcpServers'], isA<Map<String, Object?>>());
    },
  );

  test(
    'prepareTeamLaunch writes WSL path for flashskyai trusted workspaces',
    () async {
      if (!Platform.isWindows) return;

      const sessionId = 'sess-flashsky-wsl-trust';
      await service.prepareTeamLaunch(
      workspaceId: _testWorkspaceId,
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
        cli: CliTool.flashskyai,
        workingDirectory: r'C:\Users\haung\Documents',
      );

      final metadataPath = p.join(
        _sessionFlashskyaiDir(base.path, sessionId),
        FlashskyaiConfigProfileCapability.metadataFileName,
      );
      final metadata =
          jsonDecode(await File(metadataPath).readAsString())
              as Map<String, Object?>;
      final workspaces = metadata['workspaces'] as Map<String, Object?>;
      final wslPath = workspaces['/mnt/c/Users/haung/Documents'];
      expect(wslPath, isA<Map>());
      expect((wslPath! as Map)['hasTrustDialogAccepted'], isTrue);
    },
  );

  test('ensureSessionProfile for claude backfills mcp-only metadata', () async {
    const sessionId = 'sess-mcp-only';
    final metadataPath = p.join(
      _sessionClaudeDir(base.path, sessionId),
      ClaudeConfigProfileCapability.metadataFileName,
    );
    await Directory(p.dirname(metadataPath)).create(recursive: true);
    await File(metadataPath).writeAsString(
      jsonEncode({
        'mcpServers': {
          'github': {'type': 'http', 'url': 'https://github.run.tools'},
        },
      }),
    );

    await service.ensureSessionProfile(
      _testWorkspaceId,
      sessionId,
      'team-a',
      cli: CliTool.claude,
    );

    final metadata =
        jsonDecode(await File(metadataPath).readAsString())
            as Map<String, Object?>;
    expect(metadata['hasCompletedOnboarding'], isTrue);
    expect(metadata['theme'], 'auto', reason: 'seeds auto so the TUI follows the terminal out of the box');
    expect((metadata['mcpServers'] as Map)['github'], isNotNull);
  });
}
