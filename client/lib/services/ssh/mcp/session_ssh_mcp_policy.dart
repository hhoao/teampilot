/// Claude/Cursor allow-list policy for the session SSH MCP.
///
/// Extra `mcp__ssh__*` / `Mcp(ssh:…)` lines are inert when the ssh server is
/// not in extra MCP servers. Callers merge these in the same places as catalog
/// read allows; do not thread `extraMcpServers` through permission writers.
abstract final class SessionSshMcpPolicy {
  static const claudeAllowEntries = [
    'mcp__ssh__list-servers',
    'mcp__ssh__execute-command',
    'mcp__ssh__upload',
    'mcp__ssh__download',
  ];
  static const cursorAllowEntries = [
    'Mcp(ssh:list-servers)',
    'Mcp(ssh:execute-command)',
    'Mcp(ssh:upload)',
    'Mcp(ssh:download)',
  ];
}
