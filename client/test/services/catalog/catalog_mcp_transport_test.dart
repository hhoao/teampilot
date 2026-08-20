import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/catalog/catalog_mcp_transport.dart';
import 'package:teampilot/services/cli/registry/capabilities/team_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';

class _FakeTeamBehavior implements TeamBehaviorCapability {
  const _FakeTeamBehavior({required this.supportsLocalStdioBridge});

  @override
  final bool supportsLocalStdioBridge;
  @override
  bool get supportsNativeTeam => false;
  @override
  bool get longBlockingWaitForMessage => true;
  @override
  Set<String> get doneEventNames => const {};
  @override
  bool get requiresPtyFallback => false;
  @override
  bool get usesDoorbellPush => false;
  @override
  bool get defaultForceWaitBeforeStop => true;
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}

class _FakeTool implements CliToolDefinition {
  const _FakeTool(this.id, this.capabilities);

  @override
  final CliTool id;
  @override
  bool get isLaunchSupported => true;
  @override
  final Iterable<CliCapability> capabilities;
}

CliToolRegistry _registry({
  required bool supportsBridge,
  required CliTool cli,
}) {
  final registry = CliToolRegistry();
  registry.register(
    _FakeTool(cli, [
      _FakeTeamBehavior(supportsLocalStdioBridge: supportsBridge),
    ]),
  );
  return registry;
}

void main() {
  const catalogEndpoint = 'http://127.0.0.1:4242/catalog/mcp';
  final catalogUri = Uri.parse(catalogEndpoint);

  Map<String, Object?> resolve({
    required bool supportsBridge,
    CliTool cli = CliTool.claude,
    RemoteBusBinding? remoteBinding,
    String? Function()? bridgeLocator,
  }) => resolveCatalogMcpTransportConfig(
    cliRegistry: _registry(supportsBridge: supportsBridge, cli: cli),
    catalogEndpoint: catalogUri,
    sessionId: 'sess-1',
    memberId: 'member-1',
    cli: cli,
    remoteBinding: remoteBinding,
    bridgeLocator: bridgeLocator,
  );

  test('local HTTP fallback when bridge locator returns null', () {
    final cfg = resolve(supportsBridge: true, bridgeLocator: () => null);

    expect(cfg['type'], 'http');
    expect(cfg['url'], catalogEndpoint);
    expect(cfg['command'], isNull);
    final headers = cfg['headers'] as Map;
    expect(headers[teammateBusMcpSessionHeader], 'sess-1');
    expect(headers[teammateBusMcpMemberHeader], 'member-1');
    expect(headers.containsKey(teammateBusTokenHeader), isFalse);
  });

  test(
    'local stdio uses teammate_bus_bridge with --bus-url as full catalog URL',
    () {
      const bridgePath = '/opt/teampilot/teammate_bus_bridge';
      final cfg = resolve(
        supportsBridge: true,
        bridgeLocator: () => bridgePath,
      );

      expect(
        cfg,
        teammateBusMcpServerConfigStdio(
          bridgePath: bridgePath,
          endpoint: catalogUri,
          memberId: 'member-1',
          sessionId: 'sess-1',
        ),
      );
      expect(cfg['args'], containsAllInOrder(['--bus-url', catalogEndpoint]));
      expect(cfg['args'], isNot(contains('--path')));
      expect(cfg['args'], isNot(contains('--catalog-url')));
    },
  );

  test(
    'CLI without local stdio bridge stays HTTP even when locator returns a path',
    () {
      final cfg = resolve(
        supportsBridge: false,
        cli: CliTool.cursor,
        bridgeLocator: () => '/opt/teampilot/teammate_bus_bridge',
      );

      expect(cfg['type'], 'http');
      expect(cfg['url'], catalogEndpoint);
      expect(cfg['command'], isNull);
    },
  );

  test(
    'remote uses idle HTTP port + /catalog/mcp + token, never relay argv',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
        mcpRawTunnelPort: 19090,
        mcpRelayArgv: ['/usr/bin/teammate_bus_relay', '--port', '19090'],
        mcpHttpTunnelPort: 18081,
      );
      final cfg = resolve(
        supportsBridge: true,
        remoteBinding: remote,
        bridgeLocator: () => '/opt/teampilot/teammate_bus_bridge',
      );

      expect(cfg['type'], 'http');
      expect(cfg['url'], 'http://127.0.0.1:18080$catalogMcpPath');
      expect(cfg['url'], 'http://127.0.0.1:18080/catalog/mcp');
      expect(cfg['command'], isNull);
      expect(cfg['args'], isNull);
      final headers = cfg['headers'] as Map;
      expect(headers[teammateBusMcpSessionHeader], 'sess-1');
      expect(headers[teammateBusMcpMemberHeader], 'member-1');
      expect(headers[teammateBusTokenHeader], 'bus-tok');
    },
  );

  test(
    'withCatalogMcpServer merges teampilot without replacing teammate-bus',
    () {
      final extra = <String, Map<String, Object?>>{
        teammateBusMcpServerName: teammateBusMcpServerConfig(
          endpoint: Uri.parse('http://127.0.0.1:4242/mcp'),
          memberId: 'member-1',
          sessionId: 'sess-1',
        ),
      };
      final catalogConfig = resolve(
        supportsBridge: false,
        bridgeLocator: () => null,
      );

      final merged = withCatalogMcpServer(
        extra: extra,
        catalogConfig: catalogConfig,
      );

      expect(
        merged.keys,
        containsAll([teammateBusMcpServerName, catalogMcpServerName]),
      );
      expect(merged[catalogMcpServerName], catalogConfig);
      expect(merged[teammateBusMcpServerName], extra[teammateBusMcpServerName]);
      expect(catalogMcpServerName, 'teampilot');
    },
  );
}
