import '../../models/team_config.dart';
import '../cli/registry/capabilities/team_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';
import '../team_bus/mcp/bus_bridge_locator.dart';
import '../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../team_bus/remote/member_bus_mcp_config.dart';
import 'catalog_mcp_constants.dart';

/// Catalog MCP transport for one seat (parallel to [resolveMemberBusMcpTransportConfig]).
///
/// Remote always uses the idle HTTP tunnel + [catalogMcpPath] (never relay argv).
/// Local stdio reuses `teammate_bus_bridge` with `--bus-url` set to the full
/// catalog URL — no extra flag.
Map<String, Object?> resolveCatalogMcpTransportConfig({
  required CliToolRegistry cliRegistry,
  required Uri catalogEndpoint,
  required String sessionId,
  required String memberId,
  required CliTool cli,
  RemoteBusBinding? remoteBinding,
  String? Function()? bridgeLocator,
}) {
  if (remoteBinding != null) {
    return {
      'type': 'http',
      'url':
          'http://127.0.0.1:${remoteBinding.idleHttpTunnelPort}$catalogMcpPath',
      'headers': <String, String>{
        teammateBusMcpMemberHeader: memberId,
        teammateBusMcpSessionHeader: sessionId,
        teammateBusTokenHeader: remoteBinding.token,
      },
    };
  }

  String? localBridge;
  final localNative =
      !AppStorage.isInstalled ||
      AppStorage.context.mode == StorageBackendMode.native;
  final supportsBridge =
      cliRegistry
          .capability<TeamBehaviorCapability>(cli)
          ?.supportsLocalStdioBridge ??
      false;
  if (supportsBridge && localNative) {
    localBridge = (bridgeLocator ?? BusBridgeLocator.resolve)();
  }
  if (localBridge != null) {
    return teammateBusMcpServerConfigStdio(
      bridgePath: localBridge,
      endpoint: catalogEndpoint,
      memberId: memberId,
      sessionId: sessionId,
    );
  }
  return teammateBusMcpServerConfig(
    endpoint: catalogEndpoint,
    memberId: memberId,
    sessionId: sessionId,
  );
}

Map<String, Map<String, Object?>> withCatalogMcpServer({
  required Map<String, Map<String, Object?>> extra,
  required Map<String, Object?> catalogConfig,
}) {
  return {...extra, catalogMcpServerName: catalogConfig};
}
