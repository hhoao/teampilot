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

/// MCP 配置中使用的 server 名（mcpServers 的 key）。
const teammateBusMcpServerName = 'teammate-bus';

/// 标识发起请求成员身份的 HTTP header 名。
const teammateBusMcpMemberHeader = 'X-Member';
