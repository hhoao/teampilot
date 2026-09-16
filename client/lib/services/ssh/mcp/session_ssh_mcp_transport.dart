import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../cli/registry/capabilities/team_behavior_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../team_bus/mcp/bus_bridge_locator.dart';
import '../../team_bus/mcp/teammate_bus_mcp_config.dart';
import 'session_ssh_mcp_constants.dart';

/// Whether a local mixed-workspace seat should receive the session SSH MCP.
///
/// Requires mixed topology with at least one `ssh:*` folder,
/// [Workspace.injectSessionSshMcp] not false, and a non-SSH launch kind.
bool shouldInjectSessionSshMcp({
  required Workspace workspace,
  required RuntimeKind launchKind,
}) {
  if (!workspace.injectSessionSshMcp) return false;
  if (usesSshTransport(launchKind)) return false;
  if (workspaceTopologyOf(workspace.folders) != WorkspaceTopology.mixed) {
    return false;
  }
  for (final folder in workspace.folders) {
    if (runtimeKindOfId(folder.targetId) == RuntimeKind.ssh) return true;
  }
  return false;
}

/// Session SSH MCP transport for one local seat (catalog LOCAL path only).
///
/// No remoteBinding / token branch — SSH MCP is injected only on host-local
/// seats. Claude native + [TeamBehaviorCapability.supportsLocalStdioBridge]
/// + locator path uses `teammate_bus_bridge` with `--bus-url` set to the full
/// SSH MCP URL.
Map<String, Object?> resolveSessionSshMcpTransportConfig({
  required CliToolRegistry cliRegistry,
  required Uri sessionSshMcpEndpoint,
  required String sessionId,
  required String memberId,
  required CliTool cli,
  required bool isLocalNative,
  String? Function()? bridgeLocator,
}) {
  String? localBridge;
  final supportsBridge =
      cliRegistry
          .capability<TeamBehaviorCapability>(cli)
          ?.supportsLocalStdioBridge ??
      false;
  if (supportsBridge && isLocalNative) {
    localBridge = (bridgeLocator ?? BusBridgeLocator.resolve)();
  }
  if (localBridge != null) {
    return teammateBusMcpServerConfigStdio(
      bridgePath: localBridge,
      endpoint: sessionSshMcpEndpoint,
      memberId: memberId,
      sessionId: sessionId,
    );
  }
  return teammateBusMcpServerConfig(
    endpoint: sessionSshMcpEndpoint,
    memberId: memberId,
    sessionId: sessionId,
  );
}

Map<String, Map<String, Object?>> extraMcpServersWithSessionSsh({
  required Map<String, Map<String, Object?>> extra,
  required Map<String, Object?> config,
}) => {...extra, sessionSshMcpServerName: config};
