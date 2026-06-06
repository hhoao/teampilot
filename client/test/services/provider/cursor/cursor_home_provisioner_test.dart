import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/claude_credential_link_result.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/cursor/cursor_cli_config_policy.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_provisioner.dart';
import 'package:teampilot/services/provider/cursor/cursor_provider_credentials_service.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeProvisioner provisioner;
  late CursorProviderCredentialsService credentials;
  const layout = CursorHomeLayout();
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
    prompt: '只做代码审查',
  );

  setUp(() {
    fs = InMemoryFilesystem();
    credentials = CursorProviderCredentialsService(fs: fs, basePath: base);
    provisioner = CursorHomeProvisioner(fs: fs, credentials: credentials);
  });

  group('CursorHomeProvisioner', () {
    test('provision writes bus files when port set (no provider)', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busPort: 4321,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.roleRule(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.hooksConfig(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.idleScript(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isTrue);
    });

    test('provision writes workspace trust marker for project cwd', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      const workspace = '/home/hhoa/Document/testmixed';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busPort: null,
        forceTeamLeadDelegateMode: false,
        mixed: true,
        workspacePath: workspace,
      );

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(
        memberHome,
        workspace,
      );
      expect((await fs.stat(trustPath)).isFile, isTrue);
      final trust = jsonDecode((await fs.readString(trustPath))!) as Map;
      expect(trust['workspacePath'], workspace);
    });

    test('provision merges cli-config Mcp allowlist in mixed mode', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busPort: null,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      final cliConfig = jsonDecode(
        (await fs.readString(layout.cliConfig(memberHome)))!,
      ) as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test('provision syncs auth when provider has logged-in credentials', () async {
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
        busPort: null,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect(
        fs.symlinks[layout.cliConfig(memberHome)],
        layout.cliConfig(providerHomePath),
      );
      expect((await fs.stat(layout.authJson(memberHome))).isFile, isTrue);
    });

    test('bus files contain expected content', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busPort: 4321,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      final roleRule = await fs.readString(layout.roleRule(memberHome));
      expect(roleRule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(roleRule, contains('只做代码审查'));
      expect(roleRule, contains('wait_for_message'));

      final hooksJson = jsonDecode(
        (await fs.readString(layout.hooksConfig(memberHome)))!,
      ) as Map<String, Object?>;
      final stop = (hooksJson['hooks'] as Map)['stop'] as List;
      expect(
        (stop.single as Map)['command'],
        "bash '${layout.idleScript(memberHome)}'",
      );

      final idleScript = await fs.readString(layout.idleScript(memberHome));
      expect(idleScript, contains('X-Member: planner'));
      expect(idleScript, contains('http://127.0.0.1:4321/idle'));

      final mcpJson = jsonDecode(
        (await fs.readString(layout.mcpConfig(memberHome)))!,
      ) as Map<String, Object?>;
      final servers = mcpJson['mcpServers'] as Map<String, Object?>;
      final bus = servers[teammateBusMcpServerName] as Map<String, Object?>;
      expect(bus['url'], 'http://127.0.0.1:4321/mcp');
      expect((bus['headers'] as Map)['X-Member'], 'planner');
    });

    test('skips bus files when busPort null in mixed mode', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        busPort: null,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.roleRule(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
    });

    test('ignores missing auth sync result without throwing', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: 'missing-provider',
        member: member,
        busPort: 4321,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.cliConfig(memberHome))).isFile, isTrue);
      final cliConfig = jsonDecode(
        (await fs.readString(layout.cliConfig(memberHome)))!,
      ) as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isTrue);
    });

    test('syncAuthToMemberHome still returns missing for empty provider store', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      final result = await credentials.syncAuthToMemberHome(
        'empty',
        memberHome,
      );
      expect(result, CredentialLinkResult.missing);
    });
  });
}
