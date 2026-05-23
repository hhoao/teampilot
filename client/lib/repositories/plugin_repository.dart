import 'dart:convert';
import '../models/plugin.dart';
import '../services/app_storage.dart';
import '../services/flashskyai_storage_roots.dart';

class PluginRepository {
  PluginRepository({FlashskyaiStorageRoots? storageRoots})
      : _storageRoots = storageRoots;

  final FlashskyaiStorageRoots? _storageRoots;

  Future<List<Plugin>> loadAll() async {
    final path = _storageRoots != null
        ? (await _storageRoots.resolve()).pluginsJsonPath
        : AppStorage.paths.pluginsJson;
    final fs = _storageRoots != null
        ? (await _storageRoots.resolve()).fs
        : AppStorage.fs;
    final stat = await fs.stat(path);
    if (!stat.isFile) return const [];
    final text = await fs.readString(path);
    if (text == null || text.isEmpty) return const [];
    final root = (jsonDecode(text) as Map).cast<String, Object?>();
    final list = (root['plugins'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList();
    return list;
  }

  Future<Plugin?> findById(String id) async {
    final list = await loadAll();
    try {
      return list.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
