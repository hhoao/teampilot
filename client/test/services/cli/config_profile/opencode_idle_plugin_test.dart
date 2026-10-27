import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/chat/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/cli/opencode/capabilities/awareness_plugin.dart';
import 'package:teampilot/services/cli/opencode/capabilities/idle_plugin.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  Future<SessionHomeContribution> contribute(
    OpencodeProviderCapability capability,
    ConfigProfileLaunchContext ctx,
  ) => capability.materializeSessionHome(
    sessionHomeContextFromLaunch(ctx, CliTool.opencode),
  );

  Future<SessionHomeContribution> materializeOpenCode(
    ConfigProfileLaunchContext ctx,
  ) => contribute(OpencodeProviderCapability(storage: fakeHomeStorage()), ctx);

  test('idle plugin source re-prompts on decision:block', () {
    expect(opencodeIdlePluginSource, contains('session.idle'));
    expect(opencodeIdlePluginSource, contains('session.next.step.ended'));
    expect(opencodeIdlePluginSource, contains('"decision":"block"'));
    expect(opencodeIdlePluginSource, contains('ctx.session.prompt'));
    expect(opencodeIdlePluginSource, contains('wait_for_message'));
    expect(
      opencodeIdlePluginSource,
      contains('<teambus type=\\"stop_reason\\">'),
    );
  });

  test(
    'mixed contributeLaunch writes idle plugin and opencode.json entry',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_idle_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
        storage: fakeHomeStorage(),
      );
      final capability = OpencodeProviderCapability(storage: fakeHomeStorage());
      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.opencode,
        teamMode: TeamMode.mixed,
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      await contribute(
        capability,
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          paths: service,
          catalog: service,
          busIdle: MemberBusIdleEndpoint(
            url: 'http://127.0.0.1:54321/idle',
            sessionId: 'session-1',
          ),
        ),
      );

      final opencodeDir = service.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        'opencode',
        memberId: scope.memberId,
      );
      final pluginPath = '$opencodeDir/$opencodeIdlePluginFileName';
      expect(await fs.stat(pluginPath), isNotNull);
      expect(await fs.readString(pluginPath), opencodeIdlePluginSource);

      final configPath =
          '$opencodeDir/${OpencodeProviderCapability.opencodeConfigFileName}';
      final raw = await fs.readString(configPath);
      expect(raw, isNotNull);
      final config = jsonDecode(raw!) as Map<String, dynamic>;
      final plugin = config['plugins'] as List;
      expect(
        plugin.map((e) => e is String ? e : (e as Map)['package']),
        containsAll(<String>[
          './$opencodeIdlePluginFileName',
          './$opencodeAwarenessPluginFileName',
        ]),
      );
      final idleEntry =
          plugin.firstWhere(
                (e) =>
                    e is Map && e['package'] == './$opencodeIdlePluginFileName',
              )
              as Map;
      expect(idleEntry['package'], './$opencodeIdlePluginFileName');
      final opts = idleEntry['options'] as Map;
      expect(opts['member'], 'm1');
      expect(opts['port'], 54321);
      expect(opts['session'], 'session-1');

      final mcp = (config['mcp'] as Map)['servers'] as Map;
      final bus = mcp[teammateBusMcpServerName] as Map;
      expect(bus['type'], 'remote');
      expect(bus['url'], 'http://127.0.0.1:54321/mcp');
      expect(bus['disabled'], false);
      final headers = bus['headers'] as Map;
      expect(headers[teammateBusMcpMemberHeader], 'm1');
      expect(headers[teammateBusMcpSessionHeader], 'session-1');
    },
  );

  test('mergeOpencodeIdlePlugin replaces stale same-member entry when the '
      'bus port changes', () {
    final once = mergeOpencodeIdlePlugin(const {}, 'm1', 54321);
    final twice = mergeOpencodeIdlePlugin(once, 'm1', 65432);
    final plugin = twice['plugins'] as List;
    expect(plugin, hasLength(1));
    final entry = plugin.first as Map;
    expect(entry['package'], './$opencodeIdlePluginFileName');
    final opts = entry['options'] as Map;
    expect(opts['member'], 'm1');
    expect(opts['port'], 65432);
  });

  test('mergeOpencodeTeammateBusMcp preserves existing mcp entries', () {
    final merged = mergeOpencodeTeammateBusMcp(
      <String, Object?>{
        'mcp': <String, Object?>{
          'servers': <String, Object?>{
            'other': <String, Object?>{
              'type': 'local',
              'command': <String>['x'],
            },
          },
        },
      },
      'm1',
      54321,
      sessionId: 'session-1',
    );
    final mcp = (merged['mcp'] as Map)['servers'] as Map;
    expect(mcp.keys, containsAll(<String>['other', teammateBusMcpServerName]));
    final bus = mcp[teammateBusMcpServerName] as Map;
    expect(bus['type'], 'remote');
    expect(bus['url'], 'http://127.0.0.1:54321/mcp');
    expect(bus['disabled'], false);
    final headers = (bus['headers'] as Map).cast<String, Object?>();
    expect(headers[teammateBusMcpMemberHeader], 'm1');
    expect(headers[teammateBusMcpSessionHeader], 'session-1');
  });

  test('mergeOpencodeDefaultModel stamps provider/model for the TUI', () {
    expect(
      mergeOpencodeDefaultModel(
        const <String, Object?>{'plugins': <Object?>[]},
        providerId: ' opencode-go ',
        modelId: ' deepseek-v4-flash ',
      )['model'],
      'opencode-go/deepseek-v4-flash',
    );
    expect(
      mergeOpencodeDefaultModel(
        const <String, Object?>{},
        providerId: '',
        modelId: 'gpt-5',
      )['model'],
      'gpt-5',
    );
    expect(
      mergeOpencodeDefaultModel(
        const <String, Object?>{'model': 'keep'},
        providerId: 'x',
        modelId: '',
      )['model'],
      'keep',
    );
  });

  test('mergeOpencodeDefaultAgent stamps default_agent', () {
    expect(
      mergeOpencodeDefaultAgent(
        const <String, Object?>{},
        ' build ',
      )['default_agent'],
      'build',
    );
    expect(
      mergeOpencodeDefaultAgent(const <String, Object?>{
        'default_agent': 'keep',
      }, ''),
      const <String, Object?>{'default_agent': 'keep'},
    );
  });

  test('opencodeStagingProviderKey prefers subscription over catalog id', () {
    const row = AppProviderConfig(
      id: 'opencode-go-2',
      cli: CliTool.opencode,
      name: 'Go work',
      config: {OpencodeProviderConfigKeys.subscription: 'opencode-go'},
    );
    expect(opencodeStagingProviderKey(row), 'opencode-go');
  });

  test('mergeOpencodeProvider uses subscription namespace', () {
    final merged = mergeOpencodeProvider(
      const <String, Object?>{},
      const AppProviderConfig(
        id: 'tp-go-home',
        cli: CliTool.opencode,
        name: 'Go home',
        apiKey: 'sk-test',
        baseUrl: 'https://opencode.ai/zen/go/v1',
        config: {OpencodeProviderConfigKeys.subscription: 'opencode-go'},
      ),
    );
    final providers = merged['providers'] as Map;
    expect(providers.keys, contains('opencode-go'));
    expect(providers.keys, isNot(contains('tp-go-home')));
  });

  test('mergeOpencodeDefaultModel registers model under provider key', () {
    final merged = mergeOpencodeDefaultModel(
      const <String, Object?>{},
      providerId: 'opencode-go',
      modelId: 'deepseek-v4.1-flash',
    );
    expect(merged['model'], 'opencode-go/deepseek-v4.1-flash');
    final models =
        ((merged['providers'] as Map)['opencode-go'] as Map)['models'] as Map;
    expect(models.keys, contains('deepseek-v4.1-flash'));
  });

  test('mergeOpencodeProvider writes apiKey/baseURL into provider options', () {
    final merged = mergeOpencodeProvider(
      <String, Object?>{
        'providers': <String, Object?>{
          'existing': <String, Object?>{'settings': <String, Object?>{}},
        },
      },
      const AppProviderConfig(
        id: 'my-openai',
        cli: CliTool.opencode,
        name: 'My OpenAI',
        apiKey: 'sk-test',
        baseUrl: 'https://api.example.com/v1',
        defaultModel: 'proxy-model',
        config: <String, Object?>{'npm': '@ai-sdk/openai-compatible'},
      ),
    );
    final providers = merged['providers'] as Map;
    expect(providers.keys, containsAll(<String>['existing', 'my-openai']));
    final entry = providers['my-openai'] as Map;
    expect(entry['package'], 'aisdk:@ai-sdk/openai-compatible');
    final options = entry['settings'] as Map;
    expect(options['apiKey'], 'sk-test');
    expect(options['baseURL'], 'https://api.example.com/v1');
    final models = entry['models'] as Map;
    expect(models['proxy-model'], isA<Map>());
    expect((models['proxy-model'] as Map)['name'], 'proxy-model');
  });

  test(
    'mixed team launch writes provider creds, AGENTS.md, and OPENCODE_CONFIG_DIR',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_team_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
        storage: fakeHomeStorage(),
      );

      await AppProviderRepository(
        basePath: base.path,
        fs: fs,
        storage: fakeHomeStorage(),
      ).saveProviders(CliTool.opencode, const [
        AppProviderConfig(
          id: 'team-openai',
          cli: CliTool.opencode,
          name: 'Team OpenAI',
          apiKey: 'sk-team',
          baseUrl: 'https://llm.example.com/v1',
        ),
      ]);

      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        model: 'gpt-test',
        provider: 'team-openai',
        responsibilities: 'You are the reviewer.',
      );
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.opencode,
        teamMode: TeamMode.mixed,
        members: [member],
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      final contribution = await materializeOpenCode(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          paths: service,
          catalog: service,
          busIdle: MemberBusIdleEndpoint(
            url: 'http://127.0.0.1:54321/idle',
            sessionId: 'session-1',
          ),
        ),
      );

      final opencodeDir = service.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        'opencode',
        memberId: scope.memberId,
      );

      expect(contribution.environment['OPENCODE_CONFIG_DIR'], opencodeDir);
      expect(contribution.environment.containsKey('OPENCODE'), isFalse);
      expect(
        contribution.warnings,
        isNot(contains('opencode_provider_missing')),
      );

      final agents = await fs.readString(
        '$opencodeDir/${OpencodeProviderCapability.agentsFileName}',
      );
      expect(agents, isNotNull);
      expect(agents, contains('You are the reviewer.'));

      final raw = await fs.readString(
        '$opencodeDir/${OpencodeProviderCapability.opencodeConfigFileName}',
      );
      final config = jsonDecode(raw!) as Map<String, dynamic>;
      final provider = (config['providers'] as Map)['team-openai'] as Map;
      final options = provider['settings'] as Map;
      expect(options['apiKey'], 'sk-team');
      expect(options['baseURL'], 'https://llm.example.com/v1');
      expect(config['model'], 'team-openai/gpt-test');
      // mixed-mode bus wiring still present alongside provider/identity.
      expect(config['mcp'], isNotNull);
      expect(config['plugins'], isNotNull);
    },
  );
}
