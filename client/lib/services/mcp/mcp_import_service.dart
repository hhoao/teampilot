import 'dart:convert';

import '../../models/mcp_server.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../storage/app_storage.dart';
import 'mcp_catalog_service.dart';

class McpImportConflict {
  const McpImportConflict({
    required this.existing,
    required this.incoming,
  });

  final McpServer existing;
  final McpServer incoming;
}

class McpImportPreview {
  const McpImportPreview({
    this.newServers = const [],
    this.conflicts = const [],
  });

  final List<McpServer> newServers;
  final List<McpImportConflict> conflicts;

  bool get isEmpty => newServers.isEmpty && conflicts.isEmpty;
}

/// Reads machine-level Claude / FlashskyAI global MCP configs.
class McpImportService {
  McpImportService({
    Filesystem? fs,
    String? homeDirectory,
  }) : _fs = fs ?? LocalFilesystem(),
       _home = homeDirectory ?? AppStorage.home;

  final Filesystem _fs;
  final String _home;

  Future<McpImportPreview> previewAgainst(List<McpServer> existingCatalog) async {
    final imported = await _readAllMachineServers();
    final byId = {for (final s in existingCatalog) s.id: s};
    final byConfigKey = {for (final s in existingCatalog) s.configKey: s};

    final newServers = <McpServer>[];
    final conflicts = <McpImportConflict>[];

    for (final server in imported) {
      final match = byId[server.id] ?? byConfigKey[server.configKey];
      if (match == null) {
        newServers.add(server);
      } else {
        conflicts.add(McpImportConflict(existing: match, incoming: server));
      }
    }

    return McpImportPreview(newServers: newServers, conflicts: conflicts);
  }

  Future<void> applyPreview(
    McpImportPreview preview, {
    required bool overwriteConflicts,
    required McpCatalogService catalog,
  }) async {
    for (final server in preview.newServers) {
      await catalog.upsert(server);
    }
    if (overwriteConflicts) {
      for (final conflict in preview.conflicts) {
        await catalog.upsert(
          conflict.incoming.copyWith(
            id: conflict.existing.id,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    }
  }

  Future<List<McpServer>> _readAllMachineServers() async {
    final home = _home.trim();
    if (home.isEmpty) return const [];

    final ctx = _fs.pathContext;
    final now = DateTime.now().millisecondsSinceEpoch;
    final results = <McpServer>[];

    for (final source in [
      (path: ctx.join(home, '.claude.json'), from: 'claude-user'),
      (path: ctx.join(home, '.flashskyai.json'), from: 'flashskyai-user'),
    ]) {
      final map = await _readMcpServersMap(source.path);
      for (final entry in map.entries) {
        final id = _slugId(entry.key);
        results.add(
          McpServer(
            id: id,
            name: entry.key,
            server: Map<String, Object?>.from(entry.value),
            source: McpServerSource.imported,
            importedFrom: source.from,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    return results;
  }

  Future<Map<String, Map<String, Object?>>> _readMcpServersMap(
    String path,
  ) async {
    final stat = await _fs.stat(path);
    if (!stat.isFile) return {};
    final text = await _fs.readString(path);
    if (text == null || text.trim().isEmpty) return {};
    final root = (jsonDecode(text) as Map).cast<String, Object?>();
    final raw = root['mcpServers'];
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.value is Map)
          entry.key: (entry.value as Map).cast<String, Object?>(),
    };
  }

  String _slugId(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return slug.isEmpty ? 'mcp-server' : slug;
  }
}
