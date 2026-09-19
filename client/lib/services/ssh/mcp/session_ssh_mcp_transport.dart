import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../cli/registry/capabilities/team_behavior_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../chat/team_bus/mcp/bus_bridge_locator.dart';
import '../../chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../chat/team_bus/remote/member_bus_mcp_config.dart';
import 'session_ssh_mcp_constants.dart';

/// Whether [workspace] has at least one `ssh:*` folder.
bool workspaceHasSshMcpFolder(Workspace workspace) {
  for (final folder in workspace.folders) {
    if (runtimeKindOfId(folder.targetId) == RuntimeKind.ssh) return true;
  }
  return false;
}

/// Whether session SSH MCP is enabled for this workspace (toggle + `ssh:*`).
bool workspaceSessionSshMcpEnabled(Workspace workspace) {
  return workspace.injectSessionSshMcp && workspaceHasSshMcpFolder(workspace);
}

/// Whether a seat should receive the session SSH MCP in extra MCP servers.
///
/// Requires [workspaceSessionSshMcpEnabled]. SSH/Termux launches also need a
/// [remoteBinding] (idle HTTP tunnel); local and WSL seats inject without it.
bool shouldInjectSessionSshMcp({
  required Workspace workspace,
  required RuntimeKind launchKind,
  RemoteBusBinding? remoteBinding,
}) {
  if (!workspaceSessionSshMcpEnabled(workspace)) return false;
  if (usesSshTransport(launchKind) && remoteBinding == null) return false;
  return true;
}

/// Session SSH MCP transport for one seat.
///
/// Remote always uses the idle HTTP tunnel + [sessionSshMcpPath] (never relay
/// argv). Local stdio/HTTP when [remoteBinding] is null: Claude native +
/// [TeamBehaviorCapability.supportsLocalStdioBridge] + locator path uses
/// `teammate_bus_bridge` with `--bus-url` set to the full SSH MCP URL.
Map<String, Object?> resolveSessionSshMcpTransportConfig({
  required CliToolRegistry cliRegistry,
  required Uri sessionSshMcpEndpoint,
  required String sessionId,
  required String memberId,
  required CliTool cli,
  required bool isLocalNative,
  RemoteBusBinding? remoteBinding,
  String? Function()? bridgeLocator,
}) {
  if (remoteBinding != null) {
    return {
      'type': 'http',
      'url':
          'http://127.0.0.1:${remoteBinding.idleHttpTunnelPort}$sessionSshMcpPath',
      'headers': <String, String>{
        teammateBusMcpMemberHeader: memberId,
        teammateBusMcpSessionHeader: sessionId,
        teammateBusTokenHeader: remoteBinding.token,
      },
    };
  }

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
