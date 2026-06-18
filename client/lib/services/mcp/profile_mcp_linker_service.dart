import 'dart:convert';

import '../../models/mcp_server.dart';
import '../storage/runtime_layout.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';

class ProfileMcpSyncResult {
  const ProfileMcpSyncResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Writes identity MCP snapshot to
/// `identities-runtime/{profileId}/mcp/servers.json`.
class ProfileMcpLinkerService {
  ProfileMcpLinkerService({Filesystem? fs}) : _fs = fs ?? LocalFilesystem();

  final Filesystem _fs;

  Future<ProfileMcpSyncResult> syncForIdentity({
    required String profileId,
    required List<String> mcpServerIds,
    required List<McpServer> catalog,
    required RuntimeLayout layout,
  }) async {
    final trimmedIdentityId = profileId.trim();
    if (trimmedIdentityId.isEmpty) {
      return const ProfileMcpSyncResult();
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

    final outPath = layout.identityMcpServersFile(trimmedIdentityId);
    try {
      await _fs.ensureDir(layout.identityMcpDir(trimmedIdentityId));
      await _fs.atomicWrite(
        outPath,
        const JsonEncoder.withIndent('  ').convert({
          'mcpServers': mcpServers,
          if (smitheryServerKeys.isNotEmpty)
            'smitheryServerKeys': smitheryServerKeys,
        }),
      );
      return ProfileMcpSyncResult(linked: linked, skippedMissingIds: skipped);
    } catch (e) {
      return ProfileMcpSyncResult(
        linked: linked,
        skippedMissingIds: skipped,
        errors: ['Failed to write identity MCP snapshot: $e'],
      );
    }
  }
}
