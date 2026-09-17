import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_auth_artifacts.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_cli_config_policy.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_provisioner.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_cli_cache.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeProvisioner provisioner;
  late CursorHomeLayout layout;

  const memberHome = '/data/tp/members/planner/cursor/home';

  const member = TeamMemberConfig(
    id: 'planner',
    name: 'Planner',
    responsibilities: '只做代码审查',
  );

  const localBusIdle = MemberBusIdleEndpoint(url: 'http://127.0.0.1:4321/idle');

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    provisioner = CursorHomeProvisioner(fs: fs);
  });

  group('CursorHomeProvisioner.provisionOverlayOnly', () {
    test('writes busGenerated paths and merged cli-config.json', () async {
      final chatsPath = fs.pathContext.join(
        layout.cursorDir(memberHome),
        'chats',
        'ws-hash',
        'chat-1',
        'state.json',
      );
      final projectsPath = fs.pathContext.join(
        layout.cursorDir(memberHome),
        'projects',
        'my-project',
        '.workspace-trusted',
      );
      await fs.writeString(chatsPath, '{"chat":"preserved"}');
      await fs.writeString(projectsPath, 'trusted');
      await fs.writeString(
        layout.cliConfig(memberHome),
        '{"authInfo":{"userId":"u1","authId":"a1"}}',
      );

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
      );

      for (final relative in CursorAuthArtifacts.busGenerated) {
        final path = fs.pathContext.join(
          layout.cursorDir(memberHome),
          relative,
        );
        expect((await fs.stat(path)).isFile, isTrue, reason: relative);
      }

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
      expect(cliConfig['authInfo'], isNotNull);

      expect(await fs.readString(chatsPath), '{"chat":"preserved"}');
      expect(await fs.readString(projectsPath), 'trusted');
    });

    test('merges teammate-bus MCP into existing mcp.json', () async {
      await fs.writeString(
        layout.mcpConfig(memberHome),
        jsonEncode({
          'mcpServers': {
            'context7': {'command': 'npx'},
          },
        }),
      );

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
      );

      final servers =
          (jsonDecode((await fs.readString(layout.mcpConfig(memberHome)))!)
                  as Map)['mcpServers']
              as Map;
      expect(servers.containsKey('context7'), isTrue);
      expect(servers.containsKey(teammateBusMcpServerName), isTrue);
    });

    test('uses cliConfigJson as merge base when provided', () async {
      const baseJson = '''
{"serverConfigCache":{"key":"cached"},"permissions":{"allow":["Mcp(existing:*)"]}}
''';

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        cliConfigJson: baseJson,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect(cliConfig['serverConfigCache'], isNotNull);
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Mcp(existing:*)'));
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test('cliConfigJson overlay keeps existing member authInfo', () async {
      await fs.writeString(
        layout.cliConfig(memberHome),
        '{"authInfo":{"userId":"u1","authId":"a1"}}',
      );
      const baseJson = '''
{"serverConfigCache":{"backendUrl":"https://api2.cursor.sh"},"permissions":{"allow":["Mcp(existing:*)"]}}
''';

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        cliConfigJson: baseJson,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect(cliConfig['authInfo'], {'userId': 'u1', 'authId': 'a1'});
      expect(cliConfig['serverConfigCache'], {
        'backendUrl': 'https://api2.cursor.sh',
      });
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Mcp(existing:*)'));
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test('does not seed authInfo from OS home', () async {
      const osHome = '/home/user';
      await fs.writeString(
        layout.cliConfig(osHome),
        jsonEncode({
          'authInfo': {'userId': 'real', 'authId': 'a1'},
          'serverConfigCache': {'backendUrl': 'https://api2.cursor.sh'},
        }),
      );

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        cliConfigJson:
            '{"serverConfigCache":{"backendUrl":"https://api2.cursor.sh"}}',
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect(cliConfig['authInfo'], isNull);
    });

    test('seeds plugins/cache from workspace cli cache', () async {
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
      final sessionHome = runtime.pathContext.join(
        runtime.sessionRuntimeToolDir('proj-1', 's1', 'cursor'),
        'home',
      );
      await CursorHomeProvisioner(
        fs: fs,
        runtimeLayout: runtime,
      ).provisionOverlayOnly(
        memberHome: sessionHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        workspaceId: 'proj-1',
        sessionId: 's1',
        providerId: 'acct-1',
      );

      final dest = layout.pluginsCache(sessionHome);
      final workspace = cache.workspaceToolRelPath(
        workspaceId: 'proj-1',
        tool: 'cursor',
        toolRel: 'home/.cursor/plugins/cache',
      );
      expect(await fs.readSymlinkTarget(dest), workspace);
      expect(
        await fs.readSymlinkTarget(dest),
        isNot(layout.pluginsCache(osHome)),
      );
    });

    test(
      'writes role.mdc but skips bus hooks/mcp when busIdle is null',
      () async {
        await provisioner.provisionOverlayOnly(
          memberHome: memberHome,
          member: member,
          busIdle: null,
          forceTeamLeadDelegateMode: false,
        );

        expect((await fs.stat(layout.roleRule(memberHome))).isFile, isTrue);
        expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
        expect((await fs.stat(layout.cliConfig(memberHome))).isFile, isTrue);
      },
    );

    test('does not write auth.json', () async {
      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
      );

      expect((await fs.stat(layout.authJson(memberHome))).isFile, isFalse);
    });

    test('stamps picker model after merging team-bus permissions', () async {
      await fs.writeString(
        layout.cliConfig(memberHome),
        '{"authInfo":{"userId":"u1"},"serverConfigCache":{"backendUrl":"https://api2.cursor.sh"}}',
      );

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: const TeamMemberConfig(
          id: 'planner',
          name: 'Planner',
          model: 'cursor-grok-4.6-high',
        ),
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect(cliConfig['authInfo'], {'userId': 'u1'});
      expect(cliConfig['serverConfigCache'], {
        'backendUrl': 'https://api2.cursor.sh',
      });
      expect((cliConfig['model'] as Map)['modelId'], 'grok-4.6');
      expect(cliConfig['hasChangedDefaultModel'], isTrue);
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });
  });

  group('CursorHomeProvisioner.writeHooks', () {
    test('ensures parent dirs for nested managed scripts', () async {
      // Strict fs throws on writes into missing parents — mirrors
      // Sftp/WslFilesystem whose atomicWrite does not create parents.
      final strictFs = _ParentStrictFilesystem();
      final strictLayout = CursorHomeLayout(pathContext: strictFs.pathContext);
      final strictProvisioner = CursorHomeProvisioner(fs: strictFs);
      await strictFs.ensureDir(strictLayout.cursorDir(memberHome));
      await strictFs.ensureDir(
        strictFs.pathContext.join(
          strictLayout.cursorDir(memberHome),
          CursorHomeLayout.hooksDirName,
        ),
      );

      await strictProvisioner.writeHooks(
        memberHome: memberHome,
        entries: [
          HookEntry(
            id: 'user-hook',
            source: HookSource.userLibrary,
            event: HookEvent.preToolUse,
            action: CommandHookAction.script(
              fileName: 'body.sh',
              scriptContent: 'echo hi',
            ),
          ),
        ],
        runner: null,
      );
      final nested = strictFs.pathContext.join(
        strictLayout.cursorDir(memberHome),
        CursorHomeLayout.hooksDirName,
        'user-hook',
        'body.sh',
      );
      expect((await strictFs.stat(nested)).isFile, isTrue);
      expect(await strictFs.readString(nested), 'echo hi');
    });
  });
}

/// In-memory fs whose writes fail when the parent directory is missing,
/// pinning the provisioner's own parent-dir ensuring (SFTP/WSL behavior).
class _ParentStrictFilesystem extends InMemoryFilesystem {
  @override
  Future<void> atomicWrite(String path, String content) async {
    final parent = pathContext.dirname(path);
    if (!(await stat(parent)).isDirectory) {
      throw StateError('missing parent dir: $parent');
    }
    await super.atomicWrite(path, content);
  }
}
