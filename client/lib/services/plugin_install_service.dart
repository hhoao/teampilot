import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';
import 'app_storage.dart';
import 'plugin_exceptions.dart';
import 'plugin_fetch_service.dart';
import 'plugin_manifest_service.dart';

class PluginInstallService {
  PluginInstallService({
    PluginManifestService? manifestService,
    PluginFetchService? fetchService,
  })  : _manifest = manifestService ?? PluginManifestService(),
       _fetch = fetchService ?? PluginFetchService();

  final PluginManifestService _manifest;
  final PluginFetchService _fetch;

  Future<Plugin> installFromZip(File zip) async {
    final stage = Directory.systemTemp.createTempSync('plugin-stage-');
    try {
      await _fetch.extractZip(zip, stage);
      final pluginDir = _findPluginRoot(stage) ?? stage;
      return await _installFromStaged(pluginDir, marketplace: null);
    } finally {
      if (stage.existsSync()) stage.deleteSync(recursive: true);
    }
  }

  Future<Plugin> installFromDirectory(Directory source,
      {PluginMarketplace? marketplace}) async {
    return _installFromStaged(source, marketplace: marketplace);
  }

  Future<Plugin> _installFromStaged(Directory source,
      {PluginMarketplace? marketplace}) async {
    final parsed = await _manifest.parseDirectory(source.path);
    final id = marketplace == null
        ? 'local/${_sanitize(parsed.name)}'
        : '${marketplace.owner}/${marketplace.name}/${parsed.name}';
    final dirName = id.replaceAll('/', '__');
    final installRoot = AppStorage.paths.basePath;
    final installDir = Directory(p.join(installRoot, 'plugins', dirName));
    if (installDir.existsSync()) {
      await _backup(installDir);
      installDir.deleteSync(recursive: true);
    }
    await _fetch.copyDirectory(source, installDir);

    final now = DateTime.now().millisecondsSinceEpoch;
    final plugin = Plugin(
      id: id,
      name: parsed.name,
      description: parsed.description,
      version: parsed.version,
      directory: dirName,
      marketplaceOwner: marketplace?.owner,
      marketplaceName: marketplace?.name,
      marketplaceBranch: marketplace?.branch,
      homepageUrl: parsed.homepageUrl,
      capabilities: parsed.capabilities,
      contentHash: _hashDirectory(installDir),
      installedAt: now,
      updatedAt: now,
    );
    await _persistPlugin(plugin);
    return plugin;
  }

  Future<void> uninstall(Plugin plugin) async {
    final dir = Directory(
        p.join(AppStorage.paths.basePath, 'plugins', plugin.directory));
    if (dir.existsSync()) {
      await _backup(dir);
      dir.deleteSync(recursive: true);
    }
    await _removePersisted(plugin.id);
  }

  Future<Plugin> updateInPlace(Plugin existing, Directory newSource) async {
    final backupDir = await _backup(
      Directory(
          p.join(AppStorage.paths.basePath, 'plugins', existing.directory)),
    );
    try {
      final updated = await _installFromStaged(
        newSource,
        marketplace: existing.marketplaceOwner != null
            ? PluginMarketplace(
                owner: existing.marketplaceOwner!,
                name: existing.marketplaceName!,
                branch: existing.marketplaceBranch ?? 'main',
              )
            : null,
      );
      return updated;
    } catch (e) {
      final target = Directory(
          p.join(AppStorage.paths.basePath, 'plugins', existing.directory));
      if (target.existsSync()) target.deleteSync(recursive: true);
      await _fetch.copyDirectory(backupDir, target);
      throw PluginInstallException(
          existing.id, 'update failed; restored from backup',
          cause: e);
    }
  }

  Future<Directory> _backup(Directory dir) async {
    final backupsRoot =
        Directory(p.join(AppStorage.paths.basePath, 'plugin-backups'));
    if (!backupsRoot.existsSync()) backupsRoot.createSync(recursive: true);
    final id =
        '${p.basename(dir.path)}-${DateTime.now().millisecondsSinceEpoch}';
    final backup = Directory(p.join(backupsRoot.path, id));
    await _fetch.copyDirectory(dir, backup);
    return backup;
  }

  String _hashDirectory(Directory dir) {
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final bytes = <int>[];
    for (final f in files) {
      bytes.addAll(utf8.encode(p.relative(f.path, from: dir.path)));
      bytes.addAll(f.readAsBytesSync());
    }
    return sha256.convert(bytes).toString();
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-').toLowerCase();

  Directory? _findPluginRoot(Directory stage) {
    if (File(p.join(stage.path, '.claude-plugin', 'plugin.json'))
        .existsSync()) return stage;
    for (final entry in stage.listSync()) {
      if (entry is Directory &&
          File(p.join(entry.path, '.claude-plugin', 'plugin.json'))
              .existsSync()) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _persistPlugin(Plugin plugin) async {
    final path = AppStorage.paths.pluginsJson;
    final fs = AppStorage.fs;
    final stat = await fs.stat(path);
    final existing = stat.isFile
        ? (jsonDecode((await fs.readString(path))!) as Map)
            .cast<String, Object?>()
        : <String, Object?>{};
    final list = ((existing['plugins'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList();
    list.removeWhere((p) => p.id == plugin.id);
    list.add(plugin);
    existing['plugins'] = list.map((p) => p.toJson()).toList();
    await fs.writeString(path, jsonEncode(existing));
  }

  Future<void> _removePersisted(String id) async {
    final path = AppStorage.paths.pluginsJson;
    final fs = AppStorage.fs;
    final stat = await fs.stat(path);
    if (!stat.isFile) return;
    final text = await fs.readString(path);
    if (text == null) return;
    final existing =
        (jsonDecode(text) as Map).cast<String, Object?>();
    final list = ((existing['plugins'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList()
      ..removeWhere((p) => p.id == id);
    existing['plugins'] = list.map((p) => p.toJson()).toList();
    await fs.writeString(path, jsonEncode(existing));
  }
}
