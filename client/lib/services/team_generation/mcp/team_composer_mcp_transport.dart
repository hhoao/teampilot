import 'package:path/path.dart' as p;

import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/team_behavior_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../storage/app_storage.dart';
import '../../storage/runtime_context.dart';
import '../../team_bus/mcp/bus_bridge_locator.dart';
import '../../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../team_bus/remote/member_bus_mcp_config.dart';
import 'team_composer_mcp_constants.dart';

/// Composer MCP transport for the builder session (parallel to the catalog
/// transport). Remote seats use the idle HTTP tunnel; local stdio reuses the
/// `teammate_bus_bridge` with the composer URL.
///
/// The workflow token travels only in the [TeamComposerMcpConstants.tokenHeader]
/// HTTP header — never in argv or environment variables. For the stdio bridge,
/// extra headers are appended after the standard bridge args.
Map<String, Object?> resolveTeamComposerMcpTransportConfig({
  required CliToolRegistry cliRegistry,
  required Uri composerEndpoint,
  required String sessionId,
  required String memberId,
  required CliTool cli,
  required String workflowToken,
  RemoteBusBinding? remoteBinding,
  String? Function()? bridgeLocator,
}) {
  if (remoteBinding != null) {
    return {
      'type': 'http',
      'url':
          'http://127.0.0.1:${remoteBinding.idleHttpTunnelPort}${TeamComposerMcpConstants.mcpPath}',
      'headers': <String, String>{
        teammateBusMcpMemberHeader: memberId,
        teammateBusMcpSessionHeader: sessionId,
        teammateBusTokenHeader: remoteBinding.token,
        TeamComposerMcpConstants.tokenHeader: workflowToken,
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
    final config = teammateBusMcpServerConfigStdio(
      bridgePath: localBridge,
      endpoint: composerEndpoint,
      memberId: memberId,
      sessionId: sessionId,
    );
    // Stdio cannot carry custom headers; append them as bridge args so the
    // bridge forwards [tokenHeader] on the loopback hop. The token stays in
    // the session-scoped MCP config file, never in a shared environment.
    final args = [...(config['args'] as List<Object?>? ?? const [])];
    config['args'] = [
      ...args,
      '--extra-header',
      '${TeamComposerMcpConstants.tokenHeader}:$workflowToken',
    ];
    return config;
  }
  final http = teammateBusMcpServerConfig(
    endpoint: composerEndpoint,
    memberId: memberId,
    sessionId: sessionId,
  );
  (http['headers'] as Map<String, String>)[TeamComposerMcpConstants.tokenHeader] =
      workflowToken;
  return http;
}

/// Composer loopback URL for a gateway HTTP port.
Uri teamComposerMcpEndpointForPort(int port) =>
    Uri.parse(
      'http://127.0.0.1:$port${TeamComposerMcpConstants.mcpPath}',
    );

/// Guard used by tests: true when [path] is the composer route.
bool isTeamComposerMcpPath(String path) =>
    p.posix.normalize(path) == TeamComposerMcpConstants.mcpPath;
