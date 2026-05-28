import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/mcp_registry_source.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../storage/app_storage.dart';
import '../storage/flashskyai_storage_roots.dart';

class McpRegistryConfigService {
  McpRegistryConfigService({
    FlashskyaiStorageRoots? storageRoots,
    Filesystem? fs,
    String? teampilotRoot,
  }) : _storageRoots = storageRoots,
       _teampilotRoot = teampilotRoot?.trim(),
       _fs = fs ?? LocalFilesystem();

  final FlashskyaiStorageRoots? _storageRoots;
  final String? _teampilotRoot;
  final Filesystem _fs;

  Future<String> _configPath() async {
    if (_storageRoots != null) {
      return (await _storageRoots.resolve()).mcpRegistrySourcesConfigPath;
    }
    final root = _teampilotRoot;
    if (root != null && root.isNotEmpty) {
      return AppPaths.mcpRegistrySourcesConfigPathForTeampilotRoot(root);
    }
    return AppStorage.paths.mcpRegistrySourcesConfigPath;
  }

  Future<McpRegistrySourcesConfig> load() async {
    final path = await _configPath();
    try {
      final stat = await _fs.stat(path);
      if (!stat.isFile) {
        return McpRegistrySourcesConfig.defaults();
      }
      final text = await _fs.readString(path);
      if (text == null || text.trim().isEmpty) {
        return McpRegistrySourcesConfig.defaults();
      }
      final json = jsonDecode(text);
      if (json is! Map) return McpRegistrySourcesConfig.defaults();
      return McpRegistrySourcesConfig.fromJson(json.cast<String, Object?>());
    } catch (_) {
      return McpRegistrySourcesConfig.defaults();
    }
  }

  Future<void> save(McpRegistrySourcesConfig config) async {
    final path = await _configPath();
    await _fs.ensureDir(p.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }
}
