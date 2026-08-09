import 'dart:convert';
import 'package:path/path.dart' as p;

import '../../models/plugin.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../storage/remote_file_store.dart';

class PluginRepoService {
  PluginRepoService();

  static const defaultMarketplaces = [
    PluginMarketplace(owner: 'anthropics', name: 'claude-plugins-official'),
  ];

  /// Local-only marketplace list read through an injected [Filesystem] (no
  /// [AppStorage] singleton). Falls back to [defaultMarketplaces] when the
  /// manifest is missing or unreadable.
  static Future<List<PluginMarketplace>> loadMarketplacesFor(
    Filesystem fs,
    String teampilotRoot,
  ) async {
    final path = AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(
      teampilotRoot.trim(),
    );
    final stat = await fs.stat(path);
    if (!stat.isFile) return defaultMarketplaces.toList();
    try {
      final content = await fs.readString(path);
      if (content == null || content.isEmpty) {
        return defaultMarketplaces.toList();
      }
      final cache = (json.decode(content) as Map<String, dynamic>)
          .cast<String, Object?>();
      final raw = cache['marketplaces'] as List<dynamic>?;
      if (raw == null) return defaultMarketplaces.toList();
      final list = raw
          .whereType<Map>()
          .map((m) => PluginMarketplace.fromJson(m.cast<String, Object?>()))
          .toList();
      return list.isEmpty ? defaultMarketplaces.toList() : list;
    } on Object {
      return defaultMarketplaces.toList();
    }
  }

  Future<String> _configPath() async {
    if (AppStorage.isInstalled) {
      return AppStorage.context.pluginMarketplacesConfigPath;
    }
    return AppPathsBootstrapper.current.pluginMarketplacesConfigPath;
  }

  Future<List<PluginMarketplace>> loadMarketplaces() async {
    final cache = await _readManifest();
    if (cache.isEmpty) {
      await _writeManifest({
        'marketplaces': defaultMarketplaces.map((m) => m.toJson()).toList(),
      });
      return defaultMarketplaces.toList();
    }
    final raw = cache['marketplaces'] as List<dynamic>?;
    if (raw == null) return defaultMarketplaces.toList();
    return raw
        .whereType<Map>()
        .map((m) => PluginMarketplace.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<void> saveMarketplaces(List<PluginMarketplace> list) async {
    final cache = await _readManifest();
    cache['marketplaces'] = list.map((m) => m.toJson()).toList();
    await _writeManifest(cache);
  }

  Future<void> addMarketplace(PluginMarketplace m) async {
    final list = await loadMarketplaces();
    if (list.any((x) => x.owner == m.owner && x.name == m.name)) return;
    list.add(m);
    await saveMarketplaces(list);
  }

  Future<void> removeMarketplace(String owner, String name) async {
    final list = await loadMarketplaces();
    list.removeWhere((m) => m.owner == owner && m.name == name);
    await saveMarketplaces(list);
  }

  Future<void> setEnabled(String owner, String name, bool enabled) async {
    final list = await loadMarketplaces();
    final idx = list.indexWhere((m) => m.owner == owner && m.name == name);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(enabled: enabled);
    await saveMarketplaces(list);
  }

  Future<RemoteFileStore?> _remote() async {
    if (!AppStorage.isInstalled) return null;
    final snap = AppStorage.context;
    return snap.storageIsRemote ? snap.remoteFileStore : null;
  }

  Future<Map<String, Object?>> _readManifest() async {
    final path = await _configPath();
    final remote = await _remote();
    if (remote != null) {
      final text = await remote.readFile(path);
      if (text == null || text.isEmpty) return {};
      try {
        return (json.decode(text) as Map<String, dynamic>)
            .cast<String, Object?>();
      } on FormatException catch (e) {
        appLogger.w(
          '[PluginRepoService] Corrupt plugins/marketplaces.json, resetting: $e',
        );
        return {};
      }
    }

    final stat = await AppStorage.fs.stat(path);
    if (!stat.isFile) return {};
    try {
      final content = await AppStorage.fs.readString(path);
      if (content == null) return {};
      return (json.decode(content) as Map<String, dynamic>)
          .cast<String, Object?>();
    } on FormatException catch (e) {
      appLogger.w(
        '[PluginRepoService] Corrupt plugins/marketplaces.json, resetting: $e',
      );
      return {};
    } catch (e) {
      appLogger.w(
        '[PluginRepoService] Cannot read plugins/marketplaces.json: $e',
      );
      return {};
    }
  }

  Future<void> _writeManifest(Map<String, Object?> data) async {
    final path = await _configPath();
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final remote = await _remote();
    if (remote != null) {
      final posix = p.Context(style: p.Style.posix);
      final parent = posix.dirname(path);
      if (parent.isNotEmpty && parent != '.') {
        await remote.ensureDirectory(parent);
      }
      await remote.writeFile(path, text);
      return;
    }
    await AppStorage.fs.writeString(path, text);
  }
}
