import 'dart:convert';
import 'dart:io';

import '../models/plugin.dart';
import '../services/storage/app_storage.dart';
import '../services/plugin/plugin_fetch_service.dart';
import '../services/plugin/plugin_install_service.dart';
import '../services/plugin/plugin_manifest_service.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/plugin/plugin_repo_git_service.dart';
import '../services/plugin/plugin_repo_service.dart';

class PluginRepository {
  factory PluginRepository({
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
          gitService: resolvedGit,
        );
    return PluginRepository._(
      install:
          install ??
          PluginInstallService(
            manifestService: resolvedManifest,
            fetchService: resolvedFetch,
            diskCache: resolvedCache,
          ),
      repos: repos ?? PluginRepoService(),
    );
  }

  PluginRepository._({
    required this.install,
    required this.repos,
  });

  final PluginInstallService install;
  final PluginRepoService repos;

  Future<List<Plugin>> loadAll() async {
    final path = AppStorage.isInstalled
        ? AppStorage.context.pluginsJsonPath
        : AppStorage.paths.pluginsJson;
    final fs = AppStorage.isInstalled
        ? AppStorage.context.fs
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
