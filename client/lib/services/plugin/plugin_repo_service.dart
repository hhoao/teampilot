import 'dart:convert';
import 'package:path/path.dart' as p;

import '../../models/plugin.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/storage_resolver.dart';
import '../storage/remote_file_store.dart';

class PluginRepoService {
  PluginRepoService({StorageRoots? storageRoots})
    : _storageRoots = storageRoots;

  final StorageRoots? _storageRoots;

  static const _defaults = [
    PluginMarketplace(owner: 'anthropics', name: 'claude-plugins-official'),
  ];

  Future<String> _configPath() async {
    if (_storageRoots != null) {
      return (await _storageRoots.resolve()).pluginMarketplacesConfigPath;
    }
    return AppPathsBootstrapper.current.pluginMarketplacesConfigPath;
  }

  Future<List<PluginMarketplace>> loadMarketplaces() async {
    final cache = await _readManifest();
    if (cache.isEmpty) {
      await _writeManifest({
        'marketplaces': _defaults.map((m) => m.toJson()).toList(),
      });
      return _defaults.toList();
    }
    final raw = cache['marketplaces'] as List<dynamic>?;
    if (raw == null) return _defaults.toList();
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
    if (_storageRoots == null) return null;
    final snap = await _storageRoots.resolve();
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
