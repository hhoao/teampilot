import 'dart:convert';

import '../models/plugin.dart';
import '../models/team_config.dart';
import 'app_storage.dart';
import 'cli_data_layout.dart';
import 'cli_plugin_layout.dart';
import 'cli_plugin_manifest_flavor.dart';
import 'cli_plugin_provision_cache.dart';
import 'io/filesystem.dart';
import 'plugin_repo_service.dart';
import '../utils/logger.dart';

/// Writes Claude-compatible plugin registration under a session CONFIG_DIR.
///
/// Mirrors upstream behavior: `settings.json` → `enabledPlugins`, plus
/// `plugins/installed_plugins.json` (v2) with absolute `installPath` values.
/// FlashskyAI uses the same logic with [CliPluginManifestFlavor.flashskyai].
class CliPluginRegistryService {
  CliPluginRegistryService({
    required this.fs,
    required this.teampilotRoot,
    CliDataLayout? layout,
    PluginRepoService? marketplaceCatalog,
  })  : _layout = layout ?? CliDataLayout(teampilotRoot: teampilotRoot, fs: fs),
        _marketplaceCatalog = marketplaceCatalog ?? PluginRepoService();

  final Filesystem fs;
  final String teampilotRoot;
  final CliDataLayout _layout;
  final PluginRepoService _marketplaceCatalog;

  static String? _cachedCatalogPath;
  static int? _cachedCatalogMtimeMs;
  static List<Plugin>? _cachedCatalog;

  static const _installedPluginsFileName = 'installed_plugins.json';
  static const _knownMarketplacesFileName = 'known_marketplaces.json';
  static const _localMarketplaceName = 'local';

  /// After bundles are copied into the member tool dir, register them for the CLI.
  Future<void> writeForSession({
    required String teamId,
    required String sessionId,
    required String tool,
    TeamConfig? team,
    List<Plugin>? installedCatalog,
    String? memberProvisionJson,
  }) async {
    final flavor = cliPluginManifestFlavorForTool(tool);
    if (flavor == null) return;

    final configDir = _layout.memberToolDir(teamId, sessionId, tool);
    final memberPluginsDir = _layout.memberPluginsDir(teamId, sessionId, tool);
    final pluginsStat = await fs.stat(memberPluginsDir);
    if (!pluginsStat.isDirectory) return;

    final catalog = installedCatalog ?? await _loadInstalledCatalog();
    final enabledIds = team?.pluginIds ?? const <String>[];
    final enabledById = {
      for (final p in catalog)
        if (enabledIds.isEmpty || enabledIds.contains(p.id)) p.id: p,
    };

    final pluginsDir = fs.pathContext.join(configDir, 'plugins');
    final resolvedMemberProvisionJson = memberProvisionJson ??
        await CliPluginProvisionCache.memberProvisionStampJson(
          fs: fs,
          memberPluginsDir: memberPluginsDir,
        );
    final marketplaceSourceStamps = await _marketplaceSourceStampsFromCatalog(
      catalog: catalog,
      enabledIds: enabledIds,
    );
    if (await CliPluginProvisionCache.isRegistryCurrent(
      fs: fs,
      pluginsDir: pluginsDir,
      configDir: configDir,
      tool: tool,
      flavor: flavor,
      memberProvisionStampJson: resolvedMemberProvisionJson,
      enabledPluginIds: enabledIds,
      catalog: catalog,
      marketplaceSourceStamps: marketplaceSourceStamps,
    )) {
      return;
    }

    final needsMarketplaceCatalog = _needsMarketplaceCatalog(
      catalog: catalog,
      enabledIds: enabledIds,
    );
    final marketplaceCtx = needsMarketplaceCatalog
        ? await _MarketplaceLaunchContext.fromCatalog(
            catalog: catalog,
            enabledIds: enabledIds,
            fs: fs,
            teampilotRoot: teampilotRoot,
          )
        : _MarketplaceLaunchContext.empty();

    final enabledPlugins = <String, bool>{};
    final installedV2 = <String, List<Map<String, Object?>>>{};
    final localMarketplacePlugins = <Map<String, Object?>>[];
    final marketplaceEntriesCache = <String, List<Map<String, Object?>>>{};

    var bundleCount = 0;
    final entries = await fs.listDir(memberPluginsDir);
    final scanned = await Future.wait(
      entries.map((entry) async {
        if (entry.name.startsWith('.')) return null;
        final bundlePath = fs.pathContext.join(memberPluginsDir, entry.name);
        if (!await CliPluginLayout.isPluginBundleEntry(fs, bundlePath)) {
          return null;
        }
        final root = await CliPluginLayout.resolvePluginRoot(
          fs,
          bundlePath,
          flavor: flavor,
        );
        if (root == null) return null;

        final manifest = await CliPluginLayout.readManifest(
          fs,
          root,
          flavor: flavor,
        );
        final pluginName = manifest?.name ?? entry.name;
        final version = manifest?.version ?? '0.0.0';

        final catalogPlugin = _matchCatalogPlugin(
          catalog: catalog,
          enabledById: enabledById,
          bundleDirName: entry.name,
          manifestName: pluginName,
        );

        final marketplaceKey =
            catalogPlugin?.marketplaceName ?? _localMarketplaceName;
        final cliPluginName = await _resolveCliPluginName(
          pluginsDir: pluginsDir,
          marketplaceKey: marketplaceKey,
          manifestName: pluginName,
          catalogPlugin: catalogPlugin,
          teampilotRoot: teampilotRoot,
          marketplaceEntriesCache: marketplaceEntriesCache,
        );
        final pluginId = '$cliPluginName@$marketplaceKey';
        final localMarketplacePlugin = marketplaceKey == _localMarketplaceName
            ? {
                'name': pluginName,
                'source': './$pluginName',
                'version': catalogPlugin?.version ?? version,
              }
            : null;
        return (
          pluginId: pluginId,
          installedEntry: [
            {
              'scope': 'user',
              'installPath': root,
              'version': catalogPlugin?.version ?? version,
              'installedAt': _isoNow(),
            },
          ],
          localMarketplacePlugin: localMarketplacePlugin,
        );
      }),
    );

    for (final result in scanned) {
      if (result == null) continue;
      enabledPlugins[result.pluginId] = true;
      installedV2[result.pluginId] = result.installedEntry;
      if (result.localMarketplacePlugin != null) {
        localMarketplacePlugins.add(result.localMarketplacePlugin!);
      }
      bundleCount++;
    }

    if (enabledPlugins.isEmpty) {
      return;
    }

    await fs.ensureDir(pluginsDir);
    await fs.atomicWrite(
      fs.pathContext.join(pluginsDir, _installedPluginsFileName),
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'plugins': installedV2,
      }),
    );

    final materializedMarketplaceStamps = await _writeKnownMarketplaces(
      pluginsDir: pluginsDir,
      flavor: flavor,
      marketplaceCtx: marketplaceCtx,
      localPlugins: localMarketplacePlugins,
    );

    await _mergeEnabledPluginsIntoSettings(
      configDir: configDir,
      tool: tool,
      enabledPlugins: enabledPlugins,
    );

    await CliPluginProvisionCache.writeRegistryStamp(
      fs: fs,
      pluginsDir: pluginsDir,
      tool: tool,
      flavor: flavor,
      memberProvisionStampJson: resolvedMemberProvisionJson,
      enabledPluginIds: enabledIds,
      catalog: catalog,
      marketplaceSourceStamps: materializedMarketplaceStamps,
    );
  }

  /// CLI `enabledPlugins` keys use marketplace catalog names, not bundle manifest names.
  ///
  /// Example: marketplace entry `42crunch-api-security-testing` → git-subdir
  /// `plugins/api-security-testing` whose `plugin.json` name is `api-security-testing`.
  Future<String> _resolveCliPluginName({
    required String pluginsDir,
    required String marketplaceKey,
    required String manifestName,
    required Plugin? catalogPlugin,
    required String teampilotRoot,
    required Map<String, List<Map<String, Object?>>> marketplaceEntriesCache,
  }) async {
    if (marketplaceKey == _localMarketplaceName) {
      return catalogPlugin?.name ?? manifestName;
    }

    final fromCatalog = catalogPlugin?.name;
    if (fromCatalog != null && fromCatalog.isNotEmpty) {
      final matched = await _matchMarketplaceEntryName(
        pluginsDir: pluginsDir,
        marketplaceKey: marketplaceKey,
        manifestName: manifestName,
        catalogPlugin: catalogPlugin,
        teampilotRoot: teampilotRoot,
        candidate: fromCatalog,
        marketplaceEntriesCache: marketplaceEntriesCache,
      );
      if (matched != null) return matched;
    }

    final idTail = catalogPlugin?.id.split('/').last;
    if (idTail != null && idTail.isNotEmpty) {
      final matched = await _matchMarketplaceEntryName(
        pluginsDir: pluginsDir,
        marketplaceKey: marketplaceKey,
        manifestName: manifestName,
        catalogPlugin: catalogPlugin,
        teampilotRoot: teampilotRoot,
        candidate: idTail,
        marketplaceEntriesCache: marketplaceEntriesCache,
      );
      if (matched != null) return matched;
    }

    final byManifest = await _matchMarketplaceEntryName(
      pluginsDir: pluginsDir,
      marketplaceKey: marketplaceKey,
      manifestName: manifestName,
      catalogPlugin: catalogPlugin,
      teampilotRoot: teampilotRoot,
      candidate: manifestName,
      marketplaceEntriesCache: marketplaceEntriesCache,
    );
    return byManifest ?? fromCatalog ?? manifestName;
  }

  Future<String?> _matchMarketplaceEntryName({
    required String pluginsDir,
    required String marketplaceKey,
    required String manifestName,
    required Plugin? catalogPlugin,
    required String teampilotRoot,
    required String candidate,
    required Map<String, List<Map<String, Object?>>> marketplaceEntriesCache,
  }) async {
    final entries = await _readMarketplacePluginEntries(
      pluginsDir: pluginsDir,
      marketplaceKey: marketplaceKey,
      catalogPlugin: catalogPlugin,
      teampilotRoot: teampilotRoot,
      marketplaceEntriesCache: marketplaceEntriesCache,
    );
    if (entries.isEmpty) return null;

    for (final entry in entries) {
      final name = entry['name'] as String?;
      if (name != null && name == candidate) return name;
    }

    for (final entry in entries) {
      final name = entry['name'] as String?;
      if (name == null || name.isEmpty) continue;
      if (_entryMatchesManifest(entry, manifestName)) return name;
    }

    return null;
  }

  bool _entryMatchesManifest(Map<String, Object?> entry, String manifestName) {
    final source = entry['source'];
    if (source is String) {
      return source.contains(manifestName);
    }
    if (source is Map) {
      final path = source['path'] as String?;
      if (path != null && path.contains(manifestName)) return true;
      final url = source['url'] as String?;
      if (url != null && url.contains(manifestName)) return true;
    }
    return false;
  }

  Future<List<Map<String, Object?>>> _readMarketplacePluginEntries({
    required String pluginsDir,
    required String marketplaceKey,
    required Plugin? catalogPlugin,
    required String teampilotRoot,
    Map<String, List<Map<String, Object?>>>? marketplaceEntriesCache,
  }) async {
    final cache = marketplaceEntriesCache;
    if (cache != null && cache.containsKey(marketplaceKey)) {
      return cache[marketplaceKey]!;
    }

    final candidates = <String>[
      fs.pathContext.join(
        pluginsDir,
        'marketplaces',
        marketplaceKey,
        CliPluginManifestFlavor.claude.manifestDirName,
        'marketplace.json',
      ),
      fs.pathContext.join(
        pluginsDir,
        'marketplaces',
        marketplaceKey,
        CliPluginManifestFlavor.flashskyai.manifestDirName,
        'marketplace.json',
      ),
    ];
    final owner = catalogPlugin?.marketplaceOwner;
    final branch = catalogPlugin?.marketplaceBranch ?? 'main';
    if (owner != null && owner.isNotEmpty) {
      candidates.add(
        fs.pathContext.join(
          teampilotRoot,
          'plugin-marketplace-cache',
          owner,
          '$marketplaceKey@$branch',
          CliPluginManifestFlavor.claude.manifestDirName,
          'marketplace.json',
        ),
      );
    }

    for (final path in candidates) {
      final text = await fs.readString(path);
      if (text == null || text.trim().isEmpty) continue;
      try {
        final root = (jsonDecode(text) as Map).cast<String, Object?>();
        final entries = (root['plugins'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, Object?>())
            .toList();
        cache?[marketplaceKey] = entries;
        return entries;
      } catch (_) {
        continue;
      }
    }
    cache?[marketplaceKey] = const [];
    return const [];
  }

  Plugin? _matchCatalogPlugin({
    required List<Plugin> catalog,
    required Map<String, Plugin> enabledById,
    required String bundleDirName,
    required String manifestName,
  }) {
    for (final plugin in enabledById.values) {
      if (plugin.name == manifestName) return plugin;
    }
    for (final plugin in enabledById.values) {
      if (plugin.directory == bundleDirName) return plugin;
    }
    return null;
  }

  Future<List<Map<String, Object?>>> _writeKnownMarketplaces({
    required String pluginsDir,
    required CliPluginManifestFlavor flavor,
    required _MarketplaceLaunchContext marketplaceCtx,
    required List<Map<String, Object?>> localPlugins,
  }) async {
    final now = _isoNow();
    final known = <String, Map<String, Object?>>{};
    final sourceStamps = <Map<String, Object?>>[];

    final marketplaceResults = await Future.wait(
      marketplaceCtx.enabledMarketplaces.map((entry) async {
        final name = entry.name;
        final teampilotCache = entry.cacheDir;
        final cacheStat = await fs.stat(teampilotCache);
        if (!cacheStat.isDirectory) return null;

        final stamp =
            await CliPluginProvisionCache.marketplaceSourceStampFromCacheDir(
              fs: fs,
              name: name,
              cacheDir: teampilotCache,
            ) ??
            CliPluginProvisionCache.marketplaceSourceStampEntry(
              name: name,
              teampilotCacheDir: teampilotCache,
              sourceMtimeMs: cacheStat.mtime?.millisecondsSinceEpoch ?? 0,
            );

        final cliInstallLocation = await _materializeMarketplaceForCli(
          pluginsDir: pluginsDir,
          marketplaceName: name,
          teampilotCacheDir: teampilotCache,
          flavor: flavor,
        );
        if (cliInstallLocation == null) {
          return (stamp: stamp, knownEntry: null);
        }

        return (
          stamp: stamp,
          knownEntry: MapEntry(name, {
            'source': {
              'source': 'directory',
              'path': cliInstallLocation,
            },
            'installLocation': cliInstallLocation,
            'lastUpdated': now,
          }),
        );
      }),
    );

    for (final result in marketplaceResults) {
      if (result == null) continue;
      sourceStamps.add(result.stamp);
      if (result.knownEntry != null) {
        known[result.knownEntry!.key] = result.knownEntry!.value;
      }
    }

    if (localPlugins.isNotEmpty) {
      final localInstallLocation = await _writeLocalMarketplaceStub(
        pluginsDir: pluginsDir,
        flavor: flavor,
        plugins: localPlugins,
      );
      known[_localMarketplaceName] = {
        'source': {
          'source': 'directory',
          'path': localInstallLocation,
        },
        'installLocation': localInstallLocation,
        'lastUpdated': now,
      };
    }

    if (known.isEmpty) return sourceStamps;

    await fs.atomicWrite(
      fs.pathContext.join(pluginsDir, _knownMarketplacesFileName),
      const JsonEncoder.withIndent('  ').convert(known),
    );
    return sourceStamps;
  }

  static bool _needsMarketplaceCatalog({
    required List<Plugin> catalog,
    required List<String> enabledIds,
  }) {
    final enabled = enabledIds.isEmpty
        ? catalog
        : catalog.where((p) => enabledIds.contains(p.id));
    return enabled.any(
      (p) =>
          p.marketplaceName != null && p.marketplaceName!.trim().isNotEmpty,
    );
  }

  Future<List<Map<String, Object?>>> _marketplaceSourceStampsFromCatalog({
    required List<Plugin> catalog,
    required List<String> enabledIds,
  }) async {
    final enabled = enabledIds.isEmpty
        ? catalog
        : catalog.where((p) => enabledIds.contains(p.id));
    final seen = <String>{};
    final stamps = <Map<String, Object?>>[];

    for (final plugin in enabled) {
      final name = plugin.marketplaceName?.trim();
      final owner = plugin.marketplaceOwner?.trim();
      if (name == null || name.isEmpty || owner == null || owner.isEmpty) {
        continue;
      }
      if (!seen.add(name)) continue;

      final branch = plugin.marketplaceBranch?.trim().isNotEmpty == true
          ? plugin.marketplaceBranch!.trim()
          : 'main';
      final cacheDir = fs.pathContext.join(
        teampilotRoot,
        'plugin-marketplace-cache',
        owner,
        '$name@$branch',
      );
      final stamp = await CliPluginProvisionCache.marketplaceSourceStampFromCacheDir(
        fs: fs,
        name: name,
        cacheDir: cacheDir,
      );
      if (stamp != null) stamps.add(stamp);
    }

    return stamps;
  }

  /// Links TeamPilot's git cache into `{CONFIG_DIR}/plugins/marketplaces/<name>/`.
  ///
  /// Symlink preferred; copy fallback when symlinks are unavailable. Claude Code
  /// expects marketplace data under the session plugins tree, not under
  /// `plugin-marketplace-cache`. FlashskyAI additionally needs
  /// `.flashskyai-plugin/marketplace.json` beside `.claude-plugin/`.
  Future<String?> _materializeMarketplaceForCli({
    required String pluginsDir,
    required String marketplaceName,
    required String teampilotCacheDir,
    required CliPluginManifestFlavor flavor,
  }) async {
    final ctx = fs.pathContext;
    final dest = ctx.join(pluginsDir, 'marketplaces', marketplaceName);
    if (await CliPluginProvisionCache.isMarketplaceMaterializationCurrent(
      fs: fs,
      dest: dest,
      teampilotCacheDir: teampilotCacheDir,
    )) {
      appLogger.d(
        '[CliPluginRegistry] materializeMarketplace: skipped ($marketplaceName)',
      );
      return dest;
    }

    await CliPluginLayout.linkOrCopyTree(
      fs: fs,
      source: teampilotCacheDir,
      destination: dest,
    );
    await CliPluginLayout.normalizeBundleForFlavor(fs, dest, flavor);
    final manifestPath = ctx.join(
      dest,
      CliPluginManifestFlavor.claude.manifestDirName,
      'marketplace.json',
    );
    if (!(await fs.stat(manifestPath)).isFile) {
      await fs.removeRecursive(dest);
      return null;
    }
    await CliPluginProvisionCache.writeMarketplaceSourceStamp(
      fs: fs,
      dest: dest,
      teampilotCacheDir: teampilotCacheDir,
    );
    return dest;
  }

  Future<String> _writeLocalMarketplaceStub({
    required String pluginsDir,
    required CliPluginManifestFlavor flavor,
    required List<Map<String, Object?>> plugins,
  }) async {
    final manifestDir = flavor.manifestDirName;
    final stubRoot = fs.pathContext.join(pluginsDir, 'marketplaces', _localMarketplaceName);
    final manifestPath = fs.pathContext.join(stubRoot, manifestDir, 'marketplace.json');
    await fs.ensureDir(fs.pathContext.dirname(manifestPath));
    if (!(await fs.stat(manifestPath)).isFile) {
      await fs.atomicWrite(
        manifestPath,
        const JsonEncoder.withIndent('  ').convert({
          'name': _localMarketplaceName,
          'owner': {'name': 'TeamPilot'},
          'plugins': plugins,
        }),
      );
      await CliPluginLayout.normalizeBundleForFlavor(fs, stubRoot, flavor);
    }
    return stubRoot;
  }

  Future<void> _mergeEnabledPluginsIntoSettings({
    required String configDir,
    required String tool,
    required Map<String, bool> enabledPlugins,
  }) async {
    const settingsFileName = 'settings.json';
    final settingsPath = fs.pathContext.join(configDir, settingsFileName);
    Map<String, Object?> settings = {};
    final existing = await fs.readString(settingsPath);
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        settings = (jsonDecode(existing) as Map).cast<String, Object?>();
      } catch (_) {
        settings = {};
      }
    }

    final merged = Map<String, Object?>.from(
      (settings['enabledPlugins'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    merged.addAll(enabledPlugins);
    settings['enabledPlugins'] = merged;

    await fs.atomicWrite(
      settingsPath,
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Future<List<Plugin>> _loadInstalledCatalog() async {
    final path = AppPaths.pluginsJsonForTeampilotRoot(teampilotRoot);
    final stat = await fs.stat(path);
    final mtimeMs = stat.mtime?.millisecondsSinceEpoch ?? 0;
    if (_cachedCatalogPath == path &&
        _cachedCatalogMtimeMs == mtimeMs &&
        _cachedCatalog != null) {
      return _cachedCatalog!;
    }

    final text = await fs.readString(path);
    if (text == null || text.trim().isEmpty) {
      _cachedCatalogPath = path;
      _cachedCatalogMtimeMs = mtimeMs;
      _cachedCatalog = const [];
      return _cachedCatalog!;
    }
    try {
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final catalog = (root['plugins'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
          .toList();
      _cachedCatalogPath = path;
      _cachedCatalogMtimeMs = mtimeMs;
      _cachedCatalog = catalog;
      return catalog;
    } catch (_) {
      _cachedCatalogPath = path;
      _cachedCatalogMtimeMs = mtimeMs;
      _cachedCatalog = const [];
      return _cachedCatalog!;
    }
  }

  static String _isoNow() => DateTime.now().toUtc().toIso8601String();
}

class _EnabledMarketplaceEntry {
  const _EnabledMarketplaceEntry({
    required this.name,
    required this.cacheDir,
  });

  final String name;
  final String cacheDir;
}

class _MarketplaceLaunchContext {
  _MarketplaceLaunchContext({
    required this.sourceStamps,
    required this.enabledMarketplaces,
  });

  final List<Map<String, Object?>> sourceStamps;
  final List<_EnabledMarketplaceEntry> enabledMarketplaces;

  static _MarketplaceLaunchContext empty() => _MarketplaceLaunchContext(
    sourceStamps: const [],
    enabledMarketplaces: const [],
  );

  static Future<_MarketplaceLaunchContext> fromCatalog({
    required List<Plugin> catalog,
    required List<String> enabledIds,
    required Filesystem fs,
    required String teampilotRoot,
  }) async {
    final enabled = enabledIds.isEmpty
        ? catalog
        : catalog.where((p) => enabledIds.contains(p.id));
    final stamps = <Map<String, Object?>>[];
    final enabledEntries = <_EnabledMarketplaceEntry>[];
    final seen = <String>{};

    for (final plugin in enabled) {
      final name = plugin.marketplaceName?.trim();
      final owner = plugin.marketplaceOwner?.trim();
      if (name == null || name.isEmpty || owner == null || owner.isEmpty) {
        continue;
      }
      if (!seen.add(name)) continue;

      final branch = plugin.marketplaceBranch?.trim().isNotEmpty == true
          ? plugin.marketplaceBranch!.trim()
          : 'main';
      final teampilotCache = fs.pathContext.join(
        teampilotRoot,
        'plugin-marketplace-cache',
        owner,
        '$name@$branch',
      );
      final cacheStat = await fs.stat(teampilotCache);
      if (!cacheStat.isDirectory) continue;

      final stamp = await CliPluginProvisionCache.marketplaceSourceStampFromCacheDir(
        fs: fs,
        name: name,
        cacheDir: teampilotCache,
      );
      if (stamp == null) continue;
      stamps.add(stamp);
      enabledEntries.add(
        _EnabledMarketplaceEntry(name: name, cacheDir: teampilotCache),
      );
    }

    return _MarketplaceLaunchContext(
      sourceStamps: stamps,
      enabledMarketplaces: enabledEntries,
    );
  }

  static Future<_MarketplaceLaunchContext> load({
    required List<Plugin> catalog,
    required List<String> enabledIds,
    required PluginRepoService catalogService,
    required Filesystem fs,
    required String teampilotRoot,
  }) async {
    final marketplaces = await catalogService.loadMarketplaces();
    final byName = {for (final m in marketplaces) m.name: m};
    final stamps = <Map<String, Object?>>[];
    final enabledEntries = <_EnabledMarketplaceEntry>[];
    final enabled = enabledIds.isEmpty
        ? catalog
        : catalog.where((p) => enabledIds.contains(p.id));
    final seen = <String>{};

    for (final plugin in enabled) {
      final name = plugin.marketplaceName;
      if (name == null || name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      final marketplace = byName[name];
      if (marketplace == null) continue;
      final teampilotCache = fs.pathContext.join(
        teampilotRoot,
        'plugin-marketplace-cache',
        marketplace.owner,
        '${marketplace.name}@${marketplace.branch}',
      );
      final cacheStat = await fs.stat(teampilotCache);
      if (!cacheStat.isDirectory) continue;
      stamps.add(
        CliPluginProvisionCache.marketplaceSourceStampEntry(
          name: name,
          teampilotCacheDir: teampilotCache,
          sourceMtimeMs: cacheStat.mtime?.millisecondsSinceEpoch ?? 0,
        ),
      );
      enabledEntries.add(
        _EnabledMarketplaceEntry(name: name, cacheDir: teampilotCache),
      );
    }

    return _MarketplaceLaunchContext(
      sourceStamps: stamps,
      enabledMarketplaces: enabledEntries,
    );
  }
}
