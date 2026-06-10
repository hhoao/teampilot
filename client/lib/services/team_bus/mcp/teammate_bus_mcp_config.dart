/// 单个 teammate-bus MCP server 的配置 dict（claude/flashskyai 的 http 远程格式）。
///
/// opencode 用不同的 schema（顶层 `mcp` + `type: "remote"`），见
/// `mergeOpencodeTeammateBusMcp`。
Map<String, Object?> teammateBusMcpServerConfig({
  required Uri endpoint,
  required String memberId,
}) {
  return {
    'type': 'http',
    'url': endpoint.toString(),
    'headers': {teammateBusMcpMemberHeader: memberId},
  };
}

/// 单个 teammate-bus MCP server 的 **stdio** 配置（claude mcpServers 的 command 格式）。
///
/// 让 claude 经 stdio 传输 spawn `teammate_bus_bridge`，桥接再转回同一个 loopback
/// [endpoint]。stdio 没有 HTTP 那个写死的 ~6 分钟单请求超时，`wait_for_message`
/// 因此能真正阻塞一整场（唯一上限是 claude 的应用层 MCP_TOOL_TIMEOUT=24h）。
/// [bridgePath] 由 `BusBridgeLocator.resolve()` 解析；为空时调用方应回落到
/// [teammateBusMcpServerConfig]（HTTP）。
Map<String, Object?> teammateBusMcpServerConfigStdio({
  required String bridgePath,
  required Uri endpoint,
  required String memberId,
}) {
  return {
    'command': bridgePath,
    'args': <String>[
      '--member',
      memberId,
      '--bus-url',
      endpoint.toString(),
    ],
  };
}

/// MCP 配置中使用的 server 名（mcpServers 的 key）。
const teammateBusMcpServerName = 'teammate-bus';

/// 标识发起请求成员身份的 HTTP header 名。
const teammateBusMcpMemberHeader = 'X-Member';
