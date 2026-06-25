import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/provider/credential_binding.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

void main() {
  test('mergeApprovedCustomApiKeyMetadata stores last-20 suffix', () {
    final merged = ClaudeConfigProfileCapability.mergeApprovedCustomApiKeyMetadata(
      const {},
      'sk-ant-api03-abcdefghijklmnop',
    );
    final approved =
        ((merged['customApiKeyResponses'] as Map)['approved'] as List)
            .cast<String>();
    expect(approved, contains('i03-abcdefghijklmnop'));
  });

  test('contributeLaunch sets agent-teams env in native mode', () async {
    final base = await Directory.systemTemp.createTemp('claude_cap_native_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const capability = ClaudeConfigProfileCapability();
    const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
    const team = TeamProfile(id: 'team-a', name: 'agent', cli: CliTool.claude);

    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final contribution = await capability.contributeLaunch(
      ConfigProfileLaunchContext(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        team: team,
        member: member,
        members: const [member],
        workingDirectory: '/workspace/workspace',
        paths: service,
      catalog: service,
      ),
    );

    expect(
      contribution.environment['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'],
      '1',
    );
  });

  test(
    'contributeLaunch omits agent-teams env in mixed mode',
    () async {
      final base = await Directory.systemTemp.createTemp('claude_cap_mixed_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = ClaudeConfigProfileCapability();
      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
      final repository = AppProviderRepository(basePath: base.path);
      await repository.saveProviders(CliTool.claude, [
        const AppProviderConfig(
          id: 'leaky',
          cli: CliTool.claude,
          name: 'leaky',
          category: AppProviderCategory.thirdParty,
          apiKey: 'mock-third-party-key',
          config: {
            'env': {
              'ANTHROPIC_BASE_URL': 'https://api.example.com/anthropic',
              'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
            },
            'teammateMode': 'in-process',
          },
        ),
      ]);
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        providerIdsByTool: {'claude': 'leaky'},
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
        catalog: service,
        ),
      );

      expect(
        contribution.environment,
        isNot(contains('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')),
      );
      expect(contribution.environment['CLAUDE_CODE_NO_FLICKER'], '1');

      // The member settings file must not re-enable agent-teams either: a
      // mixed member is a standalone process driven by the teammate-bus Stop
      // hook, and agent-teams mode would suppress that hook.
      final settingsPath = p.join(
        base.path,
        'workspace',
        'workspaces',
        'workspace-1',
        'sessions',
        'session-1',
        'runtime',
        'm1',
        'claude',
        'settings',
        'm1.json',
      );
      final settings =
          jsonDecode(await File(settingsPath).readAsString()) as Map;
      expect(
        (settings['env'] as Map),
        isNot(contains('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')),
      );
      expect(settings.containsKey('teammateMode'), isFalse);
      expect(
        (settings['hooks'] as Map?)?['Stop'],
        isNull,
        reason: 'no idle URL passed ??no Stop hook here',
      );

      final metadataPath = p.join(
        base.path,
        'workspace',
        'workspaces',
        'workspace-1',
        'sessions',
        'session-1',
        'runtime',
        'm1',
        'claude',
        ClaudeConfigProfileCapability.metadataFileName,
      );
      final metadata =
          jsonDecode(await File(metadataPath).readAsString()) as Map;
      final approved =
          ((metadata['customApiKeyResponses'] as Map)['approved'] as List)
              .cast<String>();
      expect(approved, contains('mock-third-party-key'));
    },
  );

  test(
    'member override keeps the provider background (haiku) model',
    () async {
      final base = await Directory.systemTemp.createTemp('claude_cap_tier_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = ClaudeConfigProfileCapability();
      final repository = AppProviderRepository(basePath: base.path);
      await repository.saveProviders(CliTool.claude, [
        const AppProviderConfig(
          id: 'tiered',
          cli: CliTool.claude,
          name: 'tiered',
          category: AppProviderCategory.thirdParty,
          baseUrl: 'https://api.example.com/anthropic',
          defaultModel: 'provider-main',
          config: {
            'env': {'ANTHROPIC_BASE_URL': 'https://api.example.com/anthropic'},
            'models': {
              'cheap': {
                'name': 'Cheap',
                'model': 'cheap-model',
                'enabled': true,
                'role': 'background',
              },
            },
          },
        ),
      ]);
      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        model: 'member-main',
      );
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        providerIdsByTool: {'claude': 'tiered'},
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
        catalog: service,
        ),
      );

      final settingsPath = p.join(
        base.path,
        'workspace',
        'workspaces',
        'workspace-1',
        'sessions',
        'session-1',
        'runtime',
        'm1',
        'claude',
        'settings',
        'm1.json',
      );
      final settings =
          jsonDecode(await File(settingsPath).readAsString()) as Map;
      final env = settings['env'] as Map;
      // Selected member model drives the main tiers ...
      expect(env['ANTHROPIC_MODEL'], 'member-main');
      expect(env['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'member-main');
      expect(env['ANTHROPIC_DEFAULT_OPUS_MODEL'], 'member-main');
      // ... while the provider's background model survives on the haiku tier.
      expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'cheap-model');
    },
  );

  test(
    'mixed member official provider links credentials from member binding',
    () async {
      final base = await Directory.systemTemp.createTemp('claude_cap_cred_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final home = p.join(base.path, 'home');
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        home: home,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = ClaudeConfigProfileCapability();
      final repository = AppProviderRepository(basePath: base.path, fs: fs);
      await repository.saveProviders(CliTool.claude, [
        const AppProviderConfig(
          id: 'leaky',
          cli: CliTool.claude,
          name: 'leaky',
          category: AppProviderCategory.thirdParty,
          config: {
            'env': {'ANTHROPIC_BASE_URL': 'https://api.example.com/anthropic'},
          },
        ),
        AppProviderConfig(
          id: 'official',
          cli: CliTool.claude,
          name: 'official',
          category: AppProviderCategory.official,
          config: withCredentialBinding({'env': {}}, CredentialBindingKind.linked),
        ),
      ]);
      await fs.writeString(
        p.join(home, '.claude', '.credentials.json'),
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );

      const member = TeamMemberConfig(
        id: 'member',
        name: 'Member',
        provider: 'official',
        model: 'sonnet',
      );
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        providerIdsByTool: {'claude': 'leaky'},
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'member',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
        catalog: service,
        ),
      );

      expect(contribution.warnings, isNot(contains('claude_credentials_missing')));
      final claudeDir = contribution.environment['CLAUDE_CONFIG_DIR']!;
      final credPath = p.join(claudeDir, '.credentials.json');
      expect(await File(credPath).exists(), isTrue);
      final linkTarget = await Link(credPath).target();
      expect(
        p.normalize(linkTarget),
        p.normalize(p.join(home, '.claude', '.credentials.json')),
      );
    },
  );
}
