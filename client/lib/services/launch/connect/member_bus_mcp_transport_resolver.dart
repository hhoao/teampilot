import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/team_behavior_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../team_bus/mcp/bus_bridge_locator.dart';
import '../../team_bus/remote/member_bus_mcp_config.dart';

/// 选择 teammate-bus MCP 的传输方式（P3b：按成员 target + 能力位分流）。
///
/// - **本地成员**：claude + 本地 PTY（native 后端）+ 桥接 exe 可解析 → stdio（经
///   `teammate_bus_bridge` 绕开 claude HTTP 的 ~6 分钟单请求死线，让
///   `wait_for_message` 真正阻塞）；其余回落到 HTTP（不破坏现状）。
/// - **远程成员**（[remoteBinding] 非空，target 为 ssh）：长阻塞 CLI
///   （claude/flashskyai/codex/opencode）→ relay-over-tunnel（stdio↔127.0.0.1:<P>，
///   带 token 握手）；cursor（门铃式）→ HTTP-over-tunnel（127.0.0.1:<P> + token header）。
///   远程成员配置指向**隧道端口 <P>**而非远端够不到的裸 loopback——即 Android mixed 修点。
///
/// [isLocalNative] reports whether the home plane is a native local backend
/// (the host loopback bridge exe is only reachable from a local native PTY).
Map<String, Object?> resolveMemberBusMcpTransportConfig({
  required CliToolRegistry cliRegistry,
  required Uri endpoint,
  required String sessionId,
  required String memberId,
  required CliTool cli,
  required bool isLocalNative,
  RemoteBusBinding? remoteBinding,
}) {
  final longBlocking =
      cliRegistry
          .capability<TeamBehaviorCapability>(cli)
          ?.longBlockingWaitForMessage ??
      true;
  String? localBridge;
  if (remoteBinding == null) {
    final supportsBridge =
        cliRegistry
            .capability<TeamBehaviorCapability>(cli)
            ?.supportsLocalStdioBridge ??
        false;
    if (supportsBridge && isLocalNative) {
      localBridge = BusBridgeLocator.resolve();
    }
  }
  return buildMemberBusMcpConfig(
    memberId: memberId,
    localEndpoint: endpoint,
    sessionId: sessionId,
    longBlocking: longBlocking,
    localStdioBridgePath: localBridge,
    remote: remoteBinding,
  );
}
