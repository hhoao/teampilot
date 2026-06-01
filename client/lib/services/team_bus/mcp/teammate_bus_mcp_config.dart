/// 单个 teammate-bus MCP server 的配置 dict（http 远程），claude/opencode 通用。
Map<String, Object?> teammateBusMcpServerConfig({
  required Uri endpoint,
  required String memberId,
}) {
  return {
    'type': 'http',
    'url': endpoint.toString(),
    'headers': {'X-Member': memberId},
  };
}

/// MCP 配置中使用的 server 名（mcpServers 的 key）。
const teammateBusMcpServerName = 'teammate-bus';
