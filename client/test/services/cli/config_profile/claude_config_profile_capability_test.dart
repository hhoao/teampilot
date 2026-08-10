import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/cli/preset_resolver.dart';
import 'package:teampilot/services/cli/claude/capabilities/config_profile.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/credential_binding.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('mergeApprovedCustomApiKeyMetadata stores last-20 suffix', () {
    final merged =
        ClaudeConfigProfileCapability.mergeApprovedCustomApiKeyMetadata(
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

  test('contributeLaunch omits agent-teams env in mixed mode', () async {
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
    final settings = jsonDecode(await File(settingsPath).readAsString()) as Map;
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
    final metadata = jsonDecode(await File(metadataPath).readAsString()) as Map;
    final approved =
        ((metadata['customApiKeyResponses'] as Map)['approved'] as List)
            .cast<String>();
    expect(approved, contains('mock-third-party-key'));
  });

  test('member override keeps the provider background (haiku) model', () async {
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
    final settings = jsonDecode(await File(settingsPath).readAsString()) as Map;
    final env = settings['env'] as Map;
    // Selected member model drives the main tiers ...
    expect(env['ANTHROPIC_MODEL'], 'member-main');
    expect(env['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'member-main');
    expect(env['ANTHROPIC_DEFAULT_OPUS_MODEL'], 'member-main');
    // ... while the provider's background model survives on the haiku tier.
    expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'cheap-model');
  });

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
          config: withCredentialBinding({
            'env': {},
          }, CredentialBindingKind.linked),
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

      expect(
        contribution.warnings,
        isNot(contains('claude_credentials_missing')),
      );
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

  test(
    'simple launch without provider links claude-official credentials',
    () async {
      final base = await Directory.systemTemp.createTemp('claude_cap_simple_');
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
          id: 'third',
          cli: CliTool.claude,
          name: 'third',
          category: AppProviderCategory.thirdParty,
          config: {
            'env': {'ANTHROPIC_BASE_URL': 'https://api.example.com'},
          },
        ),
        AppProviderConfig(
          id: 'claude-official',
          cli: CliTool.claude,
          name: 'Claude Official',
          category: AppProviderCategory.official,
          isOfficial: true,
          config: withCredentialBinding({
            'env': {},
          }, CredentialBindingKind.linked),
        ),
        AppProviderConfig(
          id: 'default',
          cli: CliTool.claude,
          name: 'Default',
          category: AppProviderCategory.official,
          isOfficial: true,
          config: withCredentialBinding({
            'env': {},
          }, CredentialBindingKind.linked),
        ),
      ]);
      await fs.writeString(
        p.join(home, '.claude', '.credentials.json'),
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );

      // Expert pack member with no provider — matches Simple history resume.
      const member = TeamMemberConfig(id: 'architect', name: 'Architect');
      final scope = LaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'workspace-1',
        sessionId: 'session-simple',
        cliTeamName: 'session-simple',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: '',
          sessionId: scope.sessionId,
          scope: scope,
          team: null,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
          catalog: service,
        ),
      );

      expect(
        contribution.warnings,
        isNot(contains('claude_credentials_missing')),
      );
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

  group('native preset inherit replicas staging', () {
    const thirdPartyPreset = CliPreset(
      id: 'preset-deepseek',
      name: 'DeepSeek',
      cli: CliTool.claude,
      provider: 'third-party',
      model: 'deepseek-chat',
      createdAt: 0,
      updatedAt: 0,
    );

    Future<({
      Directory base,
      ConfigProfileService service,
      TeamProfile team,
      List<TeamMemberConfig> launchMembers,
    })> setupFixture() async {
      final base = await Directory.systemTemp.createTemp('claude_cap_preset_');
      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
        loadGlobalPresets: () async => [thirdPartyPreset],
      );
      final repository = AppProviderRepository(basePath: base.path, fs: fs);
      await repository.saveProviders(CliTool.claude, [
        const AppProviderConfig(
          id: 'third-party',
          cli: CliTool.claude,
          name: 'Third',
          category: AppProviderCategory.thirdParty,
          apiKey: 'fixture-auth-token',
          baseUrl: 'https://api.third.example/anthropic',
        ),
      ]);

      final team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.native,
        activePresetId: thirdPartyPreset.id,
        members: [
          TeamMemberConfig(
            id: 'team-lead',
            name: 'team-lead',
            activePresetId: TeamProfile.inheritPresetId,
          ),
          TeamMemberConfig(
            id: 'developer',
            name: 'developer',
            replicas: 2,
            activePresetId: TeamProfile.inheritPresetId,
          ),
        ],
      ).normalizedLaunchConfig();

      final roster = runtimeRosterMembers(team);
      final launchMembers = resolveTeamRosterForLaunch(
        team: team,
        members: roster,
        globalPresets: [thirdPartyPreset],
      );

      return (base: base, service: service, team: team, launchMembers: launchMembers);
    }

    String memberSettingsPath(String base, String sessionId, String memberId) =>
        p.join(
          base,
          'workspace',
          'workspaces',
          'workspace-1',
          'sessions',
          sessionId,
          'runtime',
          'claude',
          'settings',
          '$memberId.json',
        );

    void expectProviderEnv(Map settings) {
      final env = settings['env'] as Map;
      final token =
          env['ANTHROPIC_AUTH_TOKEN']?.toString() ??
          env['ANTHROPIC_API_KEY']?.toString() ??
          '';
      expect(token, isNotEmpty);
      expect(env['ANTHROPIC_BASE_URL'], 'https://api.third.example/anthropic');
    }

    test(
      'member explicit preset stages its provider env, not team preset',
      () async {
        const teamPreset = CliPreset(
          id: 'preset-team',
          name: 'Team Default',
          cli: CliTool.claude,
          provider: 'team-provider',
          model: 'team-model',
          createdAt: 0,
          updatedAt: 0,
        );
        const memberPreset = CliPreset(
          id: 'preset-member',
          name: 'Member Override',
          cli: CliTool.claude,
          provider: 'member-provider',
          model: 'member-model',
          createdAt: 0,
          updatedAt: 0,
        );

        final base = await Directory.systemTemp.createTemp('claude_cap_member_preset_');
        addTearDown(() async {
          if (await base.exists()) await base.delete(recursive: true);
        });

        final fs = LocalFilesystem();
        final service = ConfigProfileService(
          basePath: base.path,
          fs: fs,
          layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
          loadGlobalPresets: () async => [teamPreset, memberPreset],
        );
        final repository = AppProviderRepository(basePath: base.path, fs: fs);
        await repository.saveProviders(CliTool.claude, [
          const AppProviderConfig(
            id: 'team-provider',
            cli: CliTool.claude,
            name: 'Team',
            category: AppProviderCategory.thirdParty,
            apiKey: 'team-token',
            baseUrl: 'https://api.team.example/anthropic',
          ),
          const AppProviderConfig(
            id: 'member-provider',
            cli: CliTool.claude,
            name: 'Member',
            category: AppProviderCategory.thirdParty,
            apiKey: 'member-token',
            baseUrl: 'https://api.member.example/anthropic',
          ),
        ]);

        final team = TeamProfile(
          id: 'team-a',
          name: 'agent',
          cli: CliTool.claude,
          teamMode: TeamMode.native,
          activePresetId: teamPreset.id,
          members: [
            TeamMemberConfig(
              id: 'inherit',
              name: 'inherit',
              activePresetId: TeamProfile.inheritPresetId,
            ),
            TeamMemberConfig(
              id: 'override',
              name: 'override',
              activePresetId: memberPreset.id,
            ),
          ],
        ).normalizedLaunchConfig();

        final launchMembers = resolveTeamRosterForLaunch(
          team: team,
          members: team.members,
          globalPresets: [teamPreset, memberPreset],
        );
        final override = launchMembers.firstWhere((m) => m.id == 'override');

        const capability = ClaudeConfigProfileCapability();
        const sessionId = 'session-member-preset';
        final scope = resolveLaunchProfileScope(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          appSessionId: sessionId,
          cliTeamName: sessionId,
        );

        await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            sessionId: scope.sessionId,
            scope: scope,
            team: team,
            member: override,
            members: launchMembers,
            workingDirectory: '/workspace/workspace',
            paths: service,
            catalog: service,
          ),
        );

        final inheritSettings =
            jsonDecode(
                  await File(
                    memberSettingsPath(base.path, sessionId, 'inherit'),
                  ).readAsString(),
                )
                as Map;
        final overrideSettings =
            jsonDecode(
                  await File(
                    memberSettingsPath(base.path, sessionId, 'override'),
                  ).readAsString(),
                )
                as Map;

        final inheritEnv = inheritSettings['env'] as Map;
        final overrideEnv = overrideSettings['env'] as Map;
        expect(inheritEnv['ANTHROPIC_BASE_URL'], 'https://api.team.example/anthropic');
        expect(overrideEnv['ANTHROPIC_BASE_URL'], 'https://api.member.example/anthropic');
        expect(
          overrideEnv['ANTHROPIC_AUTH_TOKEN']?.toString() ??
              overrideEnv['ANTHROPIC_API_KEY']?.toString(),
          'member-token',
        );
      },
    );

    test(
      'contributeLaunch stages provider env for all launch-resolved seats',
      () async {
        final fixture = await setupFixture();
        addTearDown(() async {
          if (await fixture.base.exists()) {
            await fixture.base.delete(recursive: true);
          }
        });

        const capability = ClaudeConfigProfileCapability();
        const sessionId = 'session-preset-roster';
        final lead = fixture.launchMembers.firstWhere((m) => m.id == 'team-lead');
        final scope = resolveLaunchProfileScope(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          appSessionId: sessionId,
          cliTeamName: sessionId,
        );

        await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            sessionId: scope.sessionId,
            scope: scope,
            team: fixture.team,
            member: lead,
            members: fixture.launchMembers,
            workingDirectory: '/workspace/workspace',
            paths: fixture.service,
            catalog: fixture.service,
          ),
        );

        for (final memberId in ['team-lead', 'developer-0', 'developer-1']) {
          final settingsPath = memberSettingsPath(fixture.base.path, sessionId, memberId);
          expect(await File(settingsPath).exists(), isTrue, reason: memberId);
          final settings =
              jsonDecode(await File(settingsPath).readAsString()) as Map;
          expectProviderEnv(settings);
        }
      },
    );

    test(
      'sequential contributeLaunch keeps tokens on all seat settings files',
      () async {
        final fixture = await setupFixture();
        addTearDown(() async {
          if (await fixture.base.exists()) {
            await fixture.base.delete(recursive: true);
          }
        });

        const capability = ClaudeConfigProfileCapability();
        const sessionId = 'session-preset-seq';
        final dev0 = fixture.launchMembers.firstWhere((m) => m.id == 'developer-0');
        final dev1 = fixture.launchMembers.firstWhere((m) => m.id == 'developer-1');
        final scope = resolveLaunchProfileScope(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          appSessionId: sessionId,
          cliTeamName: sessionId,
        );

        await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            sessionId: scope.sessionId,
            scope: scope,
            team: fixture.team,
            member: dev0,
            members: fixture.launchMembers,
            workingDirectory: '/workspace/workspace',
            paths: fixture.service,
            catalog: fixture.service,
          ),
        );

        await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            sessionId: scope.sessionId,
            scope: scope,
            team: fixture.team,
            member: dev1,
            members: fixture.launchMembers,
            workingDirectory: '/workspace/workspace',
            paths: fixture.service,
            catalog: fixture.service,
          ),
        );

        for (final memberId in ['team-lead', 'developer-0', 'developer-1']) {
          final settingsPath = memberSettingsPath(fixture.base.path, sessionId, memberId);
          final settings =
              jsonDecode(await File(settingsPath).readAsString()) as Map;
          expectProviderEnv(settings);
        }
      },
    );
  });
}
