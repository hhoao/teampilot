import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_link_result.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_cli_config_policy.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_provisioner.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_provider_credentials_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_cli_cache.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeProvisioner provisioner;
  late CursorProviderCredentialsService credentials;
  late CursorHomeLayout layout;
  const base = '/data/tp';

  const loggedInCliConfig = '''
{"authInfo":{"userId":"u1","authId":"a1"}}
''';

  const loggedInAuthJson = '''
{"accessToken":"at1","refreshToken":"rt1"}
''';

  Future<void> writeLoggedInProvider(String providerId) async {
    final providerHomePath = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      providerId,
      'home',
    );
    await fs.writeString(layout.cliConfig(providerHomePath), loggedInCliConfig);
    await fs.writeString(layout.authJson(providerHomePath), loggedInAuthJson);
  }

  const member = TeamMemberConfig(
    id: 'planner',
    name: 'Planner',
    responsibilities: '只做代码审查',
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    credentials = CursorProviderCredentialsService(
      fs: fs,
      basePath: base,
      storage: fakeHomeStorage(filesystem: fs),
    );
    provisioner = CursorHomeProvisioner(fs: fs, credentials: credentials);
  });

  const localBusIdle = MemberBusIdleEndpoint(url: 'http://127.0.0.1:4321/idle');

  group('CursorHomeProvisioner', () {
    test(
      'provision mirrors real home passthrough when realHomeRoot set',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        const realHome = '/home/user';
        await fs.ensureDir(realHome);
        await fs.ensureDir(fs.pathContext.join(realHome, '.pub-cache'));

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: false,
          realHomeRoot: realHome,
        );

        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(memberHome, '.pub-cache'),
          ),
          fs.pathContext.join(realHome, '.pub-cache'),
        );
        expect(
          (await fs.stat(layout.cursorDir(memberHome))).isDirectory,
          isTrue,
        );
      },
    );

    test('provision writes role.mdc in simple mode', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
      );

      final roleRule = await fs.readString(layout.roleRule(memberHome));
      expect(roleRule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(roleRule, contains('只做代码审查'));
      expect((await fs.stat(layout.hooksConfig(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
    });

    test(
      'empty role still materializes workspace-base-info extras into role.mdc',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        const emptyRoleMember = TeamMemberConfig(id: 'm1', name: 'Member');

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: emptyRoleMember,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: false,
          additionalDirectories: const ['/repo/a'],
        );

        final roleRule = await fs.readString(layout.roleRule(memberHome));
        expect(roleRule, contains('## Workspace directories'));
        expect(roleRule, contains('- /repo/a'));
      },
    );

    test(
      'empty role still materializes ssh workspace-base-info into role.mdc',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        const emptyRoleMember = TeamMemberConfig(id: 'm1', name: 'Member');

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: emptyRoleMember,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: false,
          workspaceBaseInfo: const WorkspaceBaseInfoPromptInputs(
            sshMcpInjected: true,
          ),
        );

        final roleRule = await fs.readString(layout.roleRule(memberHome));
        expect(roleRule, contains('## Remote projects'));
        expect(roleRule, contains('list-servers'));
      },
    );

    test(
      'provision preserves a prompt already written by the coordinator',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        final roleRule = layout.roleRule(memberHome);
        await fs.ensureDir(fs.pathContext.dirname(roleRule));
        await fs.writeString(roleRule, 'coordinator prompt');

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: false,
          promptAlreadyMaterialized: true,
        );

        expect(await fs.readString(roleRule), 'coordinator prompt');
      },
    );

    test(
      'provision seeds hasShownAgentCommandTip in isolated agent-cli-state',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: false,
        );

        final raw = await fs.readString(layout.agentCliState(memberHome));
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['version'], 1);
        expect(decoded['hasShownAgentCommandTip'], isTrue);
      },
    );

    test(
      'provision merges hasShownAgentCommandTip into existing agent-cli-state',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        await fs.ensureDir(layout.cursorDir(memberHome));
        await fs.writeString(
          layout.agentCliState(memberHome),
          jsonEncode({'version': 1, 'hasClearedLegacyStatsigFields': true}),
        );

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: false,
        );

        final raw = await fs.readString(layout.agentCliState(memberHome));
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['hasShownAgentCommandTip'], isTrue);
        expect(decoded['hasClearedLegacyStatsigFields'], isTrue);
      },
    );

    test('provision writes bus files when port set (no provider)', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.roleRule(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.hooksConfig(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.hooksDir(memberHome))).isDirectory, isTrue);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isTrue);
    });

    test('provision merges cli-config Mcp allowlist in mixed mode', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test(
      'provision syncs auth when provider has logged-in credentials',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        final providerHomePath = fs.pathContext.join(
          base,
          'providers',
          'cursor',
          'work',
          'home',
        );
        await writeLoggedInProvider('work');

        await provisioner.provision(
          memberHome: memberHome,
          providerId: 'work',
          member: member,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
          mixed: true,
        );

        expect(
          fs.symlinks[layout.cliConfig(memberHome)],
          layout.cliConfig(providerHomePath),
        );
        expect((await fs.stat(layout.authJson(memberHome))).isFile, isTrue);
      },
    );

    test('provision replaces auth when switching cursor providers', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      await writeLoggedInProvider('acct-a');
      final bHome = fs.pathContext.join(
        base,
        'providers',
        'cursor',
        'acct-b',
        'home',
      );
      await fs.writeString(
        layout.cliConfig(bHome),
        '{"authInfo":{"userId":"u-b","authId":"a-b"}}',
      );
      await fs.writeString(
        layout.authJson(bHome),
        '{"accessToken":"at-b","refreshToken":"rt-b"}',
      );

      await provisioner.provision(
        memberHome: memberHome,
        providerId: 'acct-a',
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
      );
      await provisioner.provision(
        memberHome: memberHome,
        providerId: 'acct-b',
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
      );

      final authBytes = await fs.readBytes(layout.authJson(memberHome));
      expect(utf8.decode(authBytes!), contains('at-b'));
    });

    test('provision merges team-bus MCP into existing mcp.json', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      await fs.writeString(
        layout.mcpConfig(memberHome),
        jsonEncode({
          'mcpServers': {
            'context7': {'command': 'npx'},
          },
        }),
      );

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      final servers =
          (jsonDecode((await fs.readString(layout.mcpConfig(memberHome)))!)
                  as Map)['mcpServers']
              as Map;
      expect(servers.containsKey('context7'), isTrue);
      expect(servers.containsKey(teammateBusMcpServerName), isTrue);
    });

    test('bus files contain expected content', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      final roleRule = await fs.readString(layout.roleRule(memberHome));
      expect(roleRule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(roleRule, contains('只做代码审查'));
      expect(roleRule, contains('wait_for_message'));

      final hooksJson =
          jsonDecode((await fs.readString(layout.hooksConfig(memberHome)))!)
              as Map<String, Object?>;
      final stop = (hooksJson['hooks'] as Map)['stop'] as List;
      final busScriptPath = fs.pathContext.join(
        layout.hooksDir(memberHome),
        'teampilot-http-teampilot-bus-idle-stop-stop.sh',
      );
      expect((stop.single as Map)['command'], "bash '$busScriptPath'");

      final sessionStart = (hooksJson['hooks'] as Map)['sessionStart'] as List;
      expect(sessionStart, isNotEmpty);
      expect(
        (sessionStart.single as Map)['command'],
        contains('teampilot-hook-teampilot-bus-awareness-sessionStart.sh'),
      );

      final busScript = await fs.readString(busScriptPath);
      expect(busScript, contains('X-Member: planner'));
      expect(busScript, contains('http://127.0.0.1:4321/idle'));
      expect(busScript, contains('"decision":"block"'));
      expect(busScript, contains('followup_message'));

      final mcpJson =
          jsonDecode((await fs.readString(layout.mcpConfig(memberHome)))!)
              as Map<String, Object?>;
      final servers = mcpJson['mcpServers'] as Map<String, Object?>;
      final bus = servers[teammateBusMcpServerName] as Map<String, Object?>;
      expect(bus['url'], 'http://127.0.0.1:4321/mcp');
      expect((bus['headers'] as Map)['X-Member'], 'planner');
    });

    test('writes role.mdc but skips bus hooks/mcp when busIdle null', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.roleRule(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.hooksConfig(memberHome))).isFile, isFalse);
    });

    test('ignores missing auth sync result without throwing', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: 'missing-provider',
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.cliConfig(memberHome))).isFile, isTrue);
      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isTrue);
    });

    test(
      'syncAuthToMemberHome still returns missing for empty provider store',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        final result = await credentials.syncAuthToMemberHome(
          'empty',
          memberHome,
        );
        expect(result, CredentialLinkResult.missing);
      },
    );

    test('provision stamps picker model into cli-config', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: const TeamMemberConfig(
          id: 'planner',
          name: 'Planner',
          model: 'cursor-grok-4.6-high',
        ),
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
        promptAlreadyMaterialized: true,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect((cliConfig['model'] as Map)['modelId'], 'grok-4.6');
      expect(cliConfig['hasChangedDefaultModel'], isTrue);
      expect(cliConfig['serverConfigCache'], isNull);
      expect(cliConfig['authInfo'], isNull);
    });

    test('provision does not copy statsig from OS home', () async {
      const osHome = '/home/user';
      await fs.writeString(layout.statsigCache(osHome), '{"statsig":true}');

      final runtime = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
      final memberHome = runtime.pathContext.join(
        runtime.sessionRuntimeToolDir('proj-1', 's1', 'cursor'),
        'home',
      );
      await CursorHomeProvisioner(fs: fs, runtimeLayout: runtime).provision(
        memberHome: memberHome,
        providerId: 'acct-1',
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
        promptAlreadyMaterialized: true,
        workspaceId: 'proj-1',
        sessionId: 's1',
      );

      expect(
        await fs.readString(layout.statsigCache(osHome)),
        '{"statsig":true}',
      );
      expect(await fs.readString(layout.statsigCache(memberHome)), isNull);
    });

    test('provision stamps composer-2.5 picker id into cli-config', () async {
      const memberHome = '/data/tp/sessions/sess/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: const TeamMemberConfig(
          id: 'solo',
          name: 'solo',
          model: 'composer-2.5',
        ),
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
        promptAlreadyMaterialized: true,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect((cliConfig['model'] as Map)['modelId'], 'composer-2.5');
      expect(cliConfig['selectedModel'], {
        'modelId': 'composer-2.5',
        'parameters': <Object?>[],
      });
      expect(cliConfig['hasChangedDefaultModel'], isTrue);
    });

    test('provision symlinks plugins/cache from workspace cli cache', () async {
      const osHome = '/home/user';
      await fs.writeString(
        fs.pathContext.join(
          layout.pluginsCache(osHome),
          'from-os',
          '.cache-complete',
        ),
        '',
      );

      final runtime = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
      final cache = WorkspaceCliCache(layout: runtime);
      final memberHome = runtime.pathContext.join(
        runtime.sessionRuntimeToolDir('proj-1', 's1', 'cursor'),
        'home',
      );
      await CursorHomeProvisioner(fs: fs, runtimeLayout: runtime).provision(
        memberHome: memberHome,
        providerId: 'acct-1',
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
        promptAlreadyMaterialized: true,
        workspaceId: 'proj-1',
        sessionId: 's1',
      );

      final dest = layout.pluginsCache(memberHome);
      final workspace = cache.workspaceToolRelPath(
        workspaceId: 'proj-1',
        tool: 'cursor',
        toolRel: 'home/.cursor/plugins/cache',
      );
      final global = cache.globalEntryPath(
        tool: 'cursor',
        providerId: 'acct-1',
        cacheRel: WorkspaceCliCache.cursorPluginsCacheRel,
      );
      expect((await fs.lstat(dest)).isSymlink, isTrue);
      expect(await fs.readSymlinkTarget(dest), workspace);
      expect(await fs.readSymlinkTarget(workspace), global);
      expect((await fs.stat(global)).isDirectory, isTrue);
      expect(
        await fs.readSymlinkTarget(dest),
        isNot(layout.pluginsCache(osHome)),
      );
    });
  });
}
