import 'dart:convert';
import 'dart:io';

import '../models/plugin.dart';
import '../services/plugin/plugin_fetch_service.dart';
import '../services/plugin/plugin_install_service.dart';
import '../services/plugin/plugin_manifest_service.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/plugin/plugin_repo_git_service.dart';
import '../services/plugin/plugin_repo_service.dart';
import '../services/storage/home_storage.dart';

class PluginRepository {
  factory PluginRepository({
    required HomeStorage storage,
    PluginManifestService? manifest,
    PluginFetchService? fetch,
    PluginRepoDiskCacheService? diskCache,
    PluginInstallService? install,
    PluginRepoService? repos,
  }) {
    final resolvedFetch = fetch ?? PluginFetchService();
    final resolvedManifest = manifest ?? PluginManifestService();
    final resolvedGit = PluginRepoGitService();
    final resolvedCache =
        diskCache ??
        PluginRepoDiskCacheService(
          filesystem: storage.fs,
          teampilotRoot: storage.appDataRoot,
          gitService: resolvedGit,
        );
    return PluginRepository._(
      storage: storage,
      install:
          install ??
          PluginInstallService(
            storage: storage,
            manifestService: resolvedManifest,
            fetchService: resolvedFetch,
            diskCache: resolvedCache,
          ),
      repos: repos ?? PluginRepoService(storage: storage),
    );
  }

  PluginRepository._({
    required this.storage,
    required this.install,
    required this.repos,
  });

  final HomeStorage storage;
  final PluginInstallService install;
  final PluginRepoService repos;

  Future<List<Plugin>> loadAll() async {
    final snap = storage.context;
    final path = snap.pluginsJsonPath;
    final fs = snap.fs;
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

  Future<List<PluginUpdateInfo>> checkUpdates(List<Plugin> installed) =>
      install.checkUpdates(installed);

  Future<Plugin> updatePlugin(Plugin plugin) => install.updatePlugin(plugin);

  Future<List<UnmanagedPlugin>> scanUnmanaged() => install.scanUnmanaged();

  Future<List<Plugin>> importUnmanaged(List<UnmanagedPlugin> plugins) =>
      install.importUnmanaged(plugins);

  Future<Plugin> installFromZip(File zip) => install.installFromZip(zip);

  Future<Plugin> installFromDirectory(
    Directory source, {
    PluginMarketplace? marketplace,
  }) => install.installFromDirectory(source, marketplace: marketplace);

  Future<void> uninstall(Plugin plugin) => install.uninstall(plugin);
}
