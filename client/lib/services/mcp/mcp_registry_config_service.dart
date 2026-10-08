import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/mcp_registry_source.dart';
import '../io/filesystem.dart';
import '../storage/app_paths.dart';

class McpRegistryConfigService {
  McpRegistryConfigService({
    required String teampilotRoot,
    required Filesystem fs,
  }) : _teampilotRoot = teampilotRoot.trim(),
       _fs = fs;

  final String _teampilotRoot;
  final Filesystem _fs;

  Future<String> _configPath() async {
    return AppPaths.mcpRegistrySourcesConfigPathForTeampilotRoot(
      _teampilotRoot,
    );
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
