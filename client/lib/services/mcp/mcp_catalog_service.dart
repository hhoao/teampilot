import 'dart:convert';

import '../../models/mcp_server.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';

class McpCatalogService {
  McpCatalogService({
    required this.catalogPath,
    Filesystem? fs,
  }) : _fs = fs ?? LocalFilesystem();

  static const catalogVersion = 1;

  final String catalogPath;
  final Filesystem _fs;

  Future<List<McpServer>> loadAll() async {
    final stat = await _fs.stat(catalogPath);
    if (!stat.isFile) return const [];
    final text = await _fs.readString(catalogPath);
    if (text == null || text.trim().isEmpty) return const [];
    final root = (jsonDecode(text) as Map).cast<String, Object?>();
    final list = (root['servers'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => McpServer.fromJson(m.cast<String, Object?>()))
        .toList();
    return list;
  }

  Future<void> saveAll(List<McpServer> servers) async {
    final parent = _fs.pathContext.dirname(catalogPath);
    await _fs.ensureDir(parent);
    final payload = {
      'version': catalogVersion,
      'servers': servers.map((s) => s.toJson()).toList(),
    };
    await _fs.atomicWrite(
      catalogPath,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> upsert(McpServer server) async {
    final all = await loadAll();
    final next = [...all.where((s) => s.id != server.id), server];
    await saveAll(next);
  }

  Future<void> deleteById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final all = await loadAll();
    await saveAll(all.where((s) => s.id != trimmed).toList());
  }
}
