import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/cursor/cursor_auth_artifacts.dart';
import 'package:teampilot/services/provider/cursor/cursor_cli_config_policy.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_provisioner.dart';
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
    prompt: '只做代码审查',
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
        final path = fs.pathContext.join(layout.cursorDir(memberHome), relative);
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

    test('skips bus files when busIdle is null', () async {
      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
      );

      expect((await fs.stat(layout.roleRule(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.cliConfig(memberHome))).isFile, isTrue);
    });

    test('does not write auth.json', () async {
      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: localBusIdle,
        forceTeamLeadDelegateMode: false,
      );

      expect((await fs.stat(layout.authJson(memberHome))).isFile, isFalse);
    });
  });
}
