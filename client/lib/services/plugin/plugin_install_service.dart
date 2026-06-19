import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../models/plugin.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';
import 'plugin_exceptions.dart';
import 'plugin_fetch_service.dart';
import 'plugin_manifest_service.dart';
import 'plugin_repo_disk_cache_service.dart';
import 'cli_plugin_layout.dart';
import '../storage/remote_file_store.dart';

class _PluginStorage {
  const _PluginStorage({
    required this.fs,
    required this.ctx,
    required this.pluginsRoot,
    required this.pluginBackupsDir,
    required this.pluginsJsonPath,
    this.remote,
  });

  final Filesystem fs;
  final p.Context ctx;
  final String pluginsRoot;
  final String pluginBackupsDir;
  final String pluginsJsonPath;
  final RemoteFileStore? remote;
}

class PluginInstallService {
  PluginInstallService({
    PluginManifestService? manifestService,
    PluginFetchService? fetchService,
    PluginRepoDiskCacheService? diskCache,
    StorageRoots? storageRoots,
  }) : _manifest = manifestService ?? PluginManifestService(),
       _fetch = fetchService ?? PluginFetchService(),
       _diskCache =
           diskCache ?? PluginRepoDiskCacheService(storageRoots: storageRoots),
       _storageRoots = storageRoots;

  final PluginManifestService _manifest;
  final PluginFetchService _fetch;
  final PluginRepoDiskCacheService _diskCache;
  final StorageRoots? _storageRoots;

  Future<_PluginStorage> _storage() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return _PluginStorage(
        fs: snap.fs,
        ctx: snap.fs.pathContext,
        pluginsRoot: snap.pluginsRoot,
        pluginBackupsDir: snap.pluginBackupsDir,
        pluginsJsonPath: snap.pluginsJsonPath,
        remote: snap.remoteFileStore,
      );
    }
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final base = AppStorage.paths.basePath;
    return _PluginStorage(
      fs: fs,
      ctx: ctx,
      pluginsRoot: AppPaths.pluginsDirForTeampilotRoot(base),
      pluginBackupsDir: AppPaths.pluginBackupsDirForTeampilotRoot(base),
      pluginsJsonPath: AppStorage.paths.pluginsJson,
    );
  }

  Future<Plugin> installFromZip(File zip) async {
    final stage = Directory.systemTemp.createTempSync('plugin-stage-');
    try {
      await _fetch.extractZip(zip, stage);
      final pluginDir = _findPluginRoot(stage) ?? stage;
      return await installFromDirectory(pluginDir, marketplace: null);
    } finally {
      if (stage.existsSync()) stage.deleteSync(recursive: true);
    }
  }

  Future<Plugin> installFromDirectory(
    Directory source, {
    PluginMarketplace? marketplace,

    /// Marketplace catalog `plugins[].name` (may differ from bundle `plugin.json` name).
    String? marketplaceEntryName,
  }) => _installFromStaged(
    source,
    marketplace: marketplace,
    marketplaceEntryName: marketplaceEntryName,
  );

  Future<Plugin> _installFromStaged(
    Directory source, {
    PluginMarketplace? marketplace,
    String? marketplaceEntryName,
  }) async {
    final storage = await _storage();
    final parsed = await _manifest.parseDirectory(source.path);
    final catalogName = marketplaceEntryName?.trim();
    final registeredName = catalogName != null && catalogName.isNotEmpty
        ? catalogName
        : parsed.name;
    final id = marketplace == null
        ? 'local/${_sanitize(registeredName)}'
        : '${marketplace.owner}/${marketplace.name}/$registeredName';
    final dirName = id.replaceAll('/', '__');
    final installDir = storage.ctx.join(storage.pluginsRoot, dirName);

    if ((await storage.fs.stat(installDir)).exists) {
      await _backupPath(installDir, storage);
      await storage.fs.removeRecursive(installDir);
    }
    await storage.fs.copyTree(source: source.path, destination: installDir);
    await CliPluginLayout.ensureNeutralPoolBundle(storage.fs, installDir);

    final now = DateTime.now().millisecondsSinceEpoch;
    final version =
        marketplace == null &&
            (parsed.version.isEmpty || parsed.version == '0.0.0')
        ? '0.0.0+local'
        : parsed.version;
    final plugin = Plugin(
      id: id,
      name: registeredName,
      description: parsed.description,
      version: version,
      directory: dirName,
      marketplaceOwner: marketplace?.owner,
      marketplaceName: marketplace?.name,
      marketplaceBranch: marketplace?.branch,
      homepageUrl: parsed.homepageUrl,
      capabilities: parsed.capabilities,
      contentHash: await _hashDirectoryPath(
        storage.fs,
        storage.ctx,
        installDir,
      ),
      installedAt: now,
      updatedAt: now,
    );
    await _persistPlugin(plugin, storage);
    return plugin;
  }

  Future<void> uninstall(Plugin plugin) async {
    final storage = await _storage();
    final dir = storage.ctx.join(storage.pluginsRoot, plugin.directory);
    if ((await storage.fs.stat(dir)).exists) {
      await _backupPath(dir, storage);
      await storage.fs.removeRecursive(dir);
    }
    await _removePersisted(plugin.id, storage);
  }

  Future<Plugin> updateInPlace(Plugin existing, Directory newSource) async {
    final storage = await _storage();
    final target = storage.ctx.join(storage.pluginsRoot, existing.directory);
    final backupDir = await _backupPath(target, storage);
    try {
      return await _installFromStaged(
        newSource,
        marketplace: existing.marketplaceOwner != null
            ? PluginMarketplace(
                owner: existing.marketplaceOwner!,
                name: existing.marketplaceName!,
                branch: existing.marketplaceBranch ?? 'main',
              )
            : null,
      );
    } catch (e) {
      if ((await storage.fs.stat(target)).exists) {
        await storage.fs.removeRecursive(target);
      }
      await storage.fs.copyTree(source: backupDir, destination: target);
      throw PluginInstallException(
        existing.id,
        'update failed; restored from backup',
        cause: e,
      );
    }
  }

  Future<List<PluginUpdateInfo>> checkUpdates(List<Plugin> installed) async {
    final updates = <PluginUpdateInfo>[];
    for (final plugin in installed) {
      if (plugin.marketplaceOwner == null || plugin.marketplaceName == null) {
        continue;
      }
      try {
        final marketplace = PluginMarketplace(
          owner: plugin.marketplaceOwner!,
          name: plugin.marketplaceName!,
          branch: plugin.marketplaceBranch ?? 'main',
        );
        final dirPath = await _diskCache.syncMarketplace(marketplace);
        final discoverable = _diskCache.parseMarketplaceManifest(
          directory: dirPath,
          marketplace: marketplace,
        );
        final pluginName = plugin.id.split('/').last;
        DiscoverablePlugin? match;
        for (final d in discoverable) {
          if (d.name == pluginName) {
            match = d;
            break;
          }
        }
        if (match == null) continue;

        final sourceDir = Directory(p.join(dirPath, match.source));
        if (!sourceDir.existsSync()) continue;
        final remoteHash = _hashLocalDirectory(sourceDir);
        if (remoteHash != plugin.contentHash) {
          updates.add(
            PluginUpdateInfo(
              id: plugin.id,
              name: plugin.name,
              currentHash: plugin.contentHash,
              remoteHash: remoteHash,
            ),
          );
        }
      } catch (e) {
        appLogger.w('[plugins] update check failed for ${plugin.id}: $e');
      }
    }
    return updates;
  }

  Future<Plugin> updatePlugin(Plugin plugin) async {
    if (plugin.marketplaceOwner == null || plugin.marketplaceName == null) {
      throw PluginInstallException(
        plugin.id,
        'Plugin has no marketplace origin to update from',
      );
    }
    final marketplace = PluginMarketplace(
      owner: plugin.marketplaceOwner!,
      name: plugin.marketplaceName!,
      branch: plugin.marketplaceBranch ?? 'main',
    );
    final dirPath = await _diskCache.syncMarketplace(marketplace);
    final discoverable = _diskCache.parseMarketplaceManifest(
      directory: dirPath,
      marketplace: marketplace,
    );
    final pluginName = plugin.id.split('/').last;
    DiscoverablePlugin? match;
    for (final d in discoverable) {
      if (d.name == pluginName) {
        match = d;
        break;
      }
    }
    if (match == null) {
      throw PluginInstallException(
        plugin.id,
        'Could not locate $pluginName in ${marketplace.fullName}',
      );
    }
    final sourceDir = Directory(p.join(dirPath, match.source));
    if (!sourceDir.existsSync()) {
      throw PluginInstallException(
        plugin.id,
        'Marketplace source missing at ${match.source}',
      );
    }
    return updateInPlace(plugin, sourceDir);
  }

  Future<List<UnmanagedPlugin>> scanUnmanaged() async {
    final storage = await _storage();
    if (!(await storage.fs.stat(storage.pluginsRoot)).isDirectory) {
      return const [];
    }

    final installed = (await _loadPersisted(
      storage,
    )).map((p) => p.directory).toSet();
    final out = <UnmanagedPlugin>[];
    for (final entry in await storage.fs.listDir(storage.pluginsRoot)) {
      if (!entry.isDirectory) continue;
      if (installed.contains(entry.name)) continue;
      final dirPath = storage.ctx.join(storage.pluginsRoot, entry.name);
      try {
        final parsed = await _manifest.parseDirectory(dirPath);
        out.add(
          UnmanagedPlugin(
            directory: entry.name,
            name: parsed.name,
            description: parsed.description,
            version: parsed.version,
            path: dirPath,
          ),
        );
      } on PluginManifestException {
        continue;
      }
    }
    return out;
  }

  Future<List<Plugin>> importUnmanaged(List<UnmanagedPlugin> plugins) async {
    final storage = await _storage();
    final added = <Plugin>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final u in plugins) {
      final parsed = await _manifest.parseDirectory(u.path);
      final id = 'local/${_sanitize(parsed.name)}';
      final plugin = Plugin(
        id: id,
        name: parsed.name,
        description: parsed.description,
        version: parsed.version,
        directory: u.directory,
        capabilities: parsed.capabilities,
        homepageUrl: parsed.homepageUrl,
        contentHash: await _hashDirectoryPath(storage.fs, storage.ctx, u.path),
        installedAt: now,
        updatedAt: now,
      );
      await _persistPlugin(plugin, storage);
      added.add(plugin);
    }
    return added;
  }

  Future<String> _backupPath(String dirPath, _PluginStorage storage) async {
    if (!(await storage.fs.stat(storage.pluginBackupsDir)).isDirectory) {
      await storage.fs.ensureDir(storage.pluginBackupsDir);
    }
    final id =
        '${p.basename(dirPath)}-${DateTime.now().millisecondsSinceEpoch}';
    final backupPath = storage.ctx.join(storage.pluginBackupsDir, id);
    await storage.fs.copyTree(source: dirPath, destination: backupPath);
    return backupPath;
  }

  String _hashLocalDirectory(Directory dir) {
    final files = dir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final bytes = <int>[];
    for (final f in files) {
      bytes.addAll(utf8.encode(p.relative(f.path, from: dir.path)));
      bytes.addAll(f.readAsBytesSync());
    }
    return sha256.convert(bytes).toString();
  }

  Future<String> _hashDirectoryPath(
    Filesystem fs,
    p.Context ctx,
    String dirPath,
  ) async {
    final relFiles = <String>[];
    await _collectRelativeFiles(fs, ctx, dirPath, '', relFiles);
    relFiles.sort();
    final bytes = <int>[];
    for (final rel in relFiles) {
      bytes.addAll(utf8.encode(rel));
      final data = await fs.readBytes(ctx.join(dirPath, rel));
      if (data != null) bytes.addAll(data);
    }
    return sha256.convert(bytes).toString();
  }

  Future<void> _collectRelativeFiles(
    Filesystem fs,
    p.Context ctx,
    String dirPath,
    String relPrefix,
    List<String> out,
  ) async {
    for (final entry in await fs.listDir(dirPath)) {
      final rel = relPrefix.isEmpty
          ? entry.name
          : ctx.join(relPrefix, entry.name);
      final full = ctx.join(dirPath, entry.name);
      if (entry.isDirectory) {
        await _collectRelativeFiles(fs, ctx, full, rel, out);
      } else {
        out.add(rel.replaceAll('\\', '/'));
      }
    }
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-').toLowerCase();

  Directory? _findPluginRoot(Directory stage) {
    if (File(
      p.join(stage.path, '.claude-plugin', 'plugin.json'),
    ).existsSync()) {
      return stage;
    }
    for (final entry in stage.listSync()) {
      if (entry is Directory &&
          File(
            p.join(entry.path, '.claude-plugin', 'plugin.json'),
          ).existsSync()) {
        return entry;
      }
    }
    return null;
  }

  Future<List<Plugin>> _loadPersisted(_PluginStorage storage) async {
    final stat = await storage.fs.stat(storage.pluginsJsonPath);
    if (!stat.isFile) return const [];
    final text = await storage.fs.readString(storage.pluginsJsonPath);
    if (text == null || text.isEmpty) return const [];
    final root = (jsonDecode(text) as Map).cast<String, Object?>();
    return (root['plugins'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<void> _persistPlugin(Plugin plugin, _PluginStorage storage) async {
    final existing = await _readManifest(storage);
    final list = ((existing['plugins'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList();
    list.removeWhere((p) => p.id == plugin.id);
    list.add(plugin);
    existing['plugins'] = list.map((p) => p.toJson()).toList();
    await storage.fs.writeString(storage.pluginsJsonPath, jsonEncode(existing));
  }

  Future<void> _removePersisted(String id, _PluginStorage storage) async {
    final stat = await storage.fs.stat(storage.pluginsJsonPath);
    if (!stat.isFile) return;
    final text = await storage.fs.readString(storage.pluginsJsonPath);
    if (text == null) return;
    final existing = (jsonDecode(text) as Map).cast<String, Object?>();
    final list =
        ((existing['plugins'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
            .toList()
          ..removeWhere((p) => p.id == id);
    existing['plugins'] = list.map((p) => p.toJson()).toList();
    await storage.fs.writeString(storage.pluginsJsonPath, jsonEncode(existing));
  }

  Future<Map<String, Object?>> _readManifest(_PluginStorage storage) async {
    final stat = await storage.fs.stat(storage.pluginsJsonPath);
    if (!stat.isFile) return {};
    final text = await storage.fs.readString(storage.pluginsJsonPath);
    if (text == null || text.isEmpty) return {};
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }
}
