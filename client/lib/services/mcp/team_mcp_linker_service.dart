import 'dart:convert';

import '../../models/mcp_server.dart';
import '../storage/runtime_layout.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';

class TeamMcpSyncResult {
  const TeamMcpSyncResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Writes team MCP snapshot to
/// `config-profiles/teams/{teamId}/mcp/servers.json`.
class TeamMcpLinkerService {
  TeamMcpLinkerService({Filesystem? fs}) : _fs = fs ?? LocalFilesystem();

  final Filesystem _fs;

  Future<TeamMcpSyncResult> syncForTeam({
    required String teamId,
    required List<String> mcpServerIds,
    required List<McpServer> catalog,
    required RuntimeLayout layout,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamMcpSyncResult();
    }

    final byId = {for (final s in catalog) s.id: s};
    final linked = <String>[];
    final skipped = <String>[];
    final mcpServers = <String, Object?>{};
    final smitheryServerKeys = <String>[];

    for (final id in mcpServerIds) {
      final server = byId[id];
      if (server == null) {
        skipped.add(id);
        continue;
      }
      if (!server.enabled) continue;
      final key = server.configKey;
      mcpServers[key] = Map<String, Object?>.from(server.server);
      if (server.smitheryHosted) {
        smitheryServerKeys.add(key);
      }
      linked.add(id);
    }

    final outPath = layout.teamMcpServersFile(trimmedTeamId);
    try {
      await _fs.ensureDir(layout.teamMcpDir(trimmedTeamId));
      await _fs.atomicWrite(
        outPath,
        const JsonEncoder.withIndent('  ').convert({
          'mcpServers': mcpServers,
          if (smitheryServerKeys.isNotEmpty)
            'smitheryServerKeys': smitheryServerKeys,
        }),
      );
      return TeamMcpSyncResult(linked: linked, skippedMissingIds: skipped);
    } catch (e) {
      return TeamMcpSyncResult(
        linked: linked,
        skippedMissingIds: skipped,
        errors: ['Failed to write team MCP snapshot: $e'],
      );
    }
  }
}
