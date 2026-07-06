import 'dart:convert';

import '../../../io/filesystem.dart';
import '../../../team_bus/mcp/teammate_bus_mcp_config.dart';

/// Claude Code project-scoped MCP file at the repo / working-directory root.
const claudeProjectMcpFileName = '.mcp.json';

/// Working-directory roots where Claude reads project-scoped `.mcp.json`.
List<String> projectMcpRootsFromLaunch({
  required String workingDirectory,
  Iterable<String> additionalDirectories = const [],
}) {
  return {
    if (workingDirectory.trim().isNotEmpty) workingDirectory.trim(),
    for (final directory in additionalDirectories)
      if (directory.trim().isNotEmpty) directory.trim(),
  }.toList(growable: false);
}

/// Drops stale project-scope teammate-bus entries before session-scoped MCP is
/// written (see [removeClaudeProjectMcpServers]).
Future<void> maybeRemoveStaleProjectTeammateBus({
  required Filesystem fs,
  Map<String, Map<String, Object?>>? extraServers,
  required Iterable<String> projectRoots,
}) async {
  if (extraServers == null ||
      !extraServers.containsKey(teammateBusMcpServerName)) {
    return;
  }
  await removeClaudeProjectMcpServers(
    fs: fs,
    projectRoots: projectRoots,
    serverNames: const [teammateBusMcpServerName],
  );
}

/// Removes [serverNames] from project `.mcp.json` under each [projectRoots].
///
/// TeamPilot provisions session-scoped teammate-bus MCP in the isolated
/// `CLAUDE_CONFIG_DIR` (user scope). Stale project `.mcp.json` copies — often
/// left after SSH reconnect with a new tunnel token/port — make Claude Code
/// report conflicting scopes and mark the server failed.
Future<void> removeClaudeProjectMcpServers({
  required Filesystem fs,
  required Iterable<String> projectRoots,
  required Iterable<String> serverNames,
}) async {
  final names = {
    for (final name in serverNames)
      if (name.trim().isNotEmpty) name.trim(),
  };
  if (names.isEmpty) return;

  for (final root in projectRoots) {
    final trimmedRoot = root.trim();
    if (trimmedRoot.isEmpty) continue;

    final path = fs.pathContext.join(trimmedRoot, claudeProjectMcpFileName);
    final stat = await fs.stat(path);
    if (!stat.isFile) continue;

    final text = await fs.readString(path);
    if (text == null || text.trim().isEmpty) continue;

    final decoded = jsonDecode(text);
    if (decoded is! Map) continue;
    final rootMap = Map<String, Object?>.from(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    final servers = (rootMap['mcpServers'] as Map?)?.cast<String, Object?>();
    if (servers == null || servers.isEmpty) continue;

    var changed = false;
    for (final name in names) {
      if (servers.remove(name) != null) {
        changed = true;
      }
    }
    if (!changed) continue;

    if (servers.isEmpty) {
      rootMap.remove('mcpServers');
    } else {
      rootMap['mcpServers'] = servers;
    }

    if (_isEffectivelyEmptyProjectMcp(rootMap)) {
      await fs.removeRecursive(path);
      continue;
    }

    await fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(rootMap),
    );
  }
}

bool _isEffectivelyEmptyProjectMcp(Map<String, Object?> root) {
  if (root.isEmpty) return true;
  if (root.length == 1 && root.containsKey('mcpServers')) {
    final servers = root['mcpServers'];
    return servers is Map && servers.isEmpty;
  }
  return false;
}
