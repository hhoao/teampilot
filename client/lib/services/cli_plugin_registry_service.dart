import 'dart:convert';

import '../models/plugin.dart';
import '../models/team_config.dart';
import 'app_storage.dart';
import 'cli_data_layout.dart';
import 'cli_plugin_layout.dart';
import 'cli_plugin_manifest_flavor.dart';
import 'io/filesystem.dart';
import 'plugin_repo_service.dart';

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

    final enabledPlugins = <String, bool>{};
    final installedV2 = <String, List<Map<String, Object?>>>{};
    final localMarketplacePlugins = <Map<String, Object?>>[];

    for (final entry in await fs.listDir(memberPluginsDir)) {
      if (!entry.isDirectory) continue;
      final bundlePath = fs.pathContext.join(memberPluginsDir, entry.name);
      final root = await CliPluginLayout.resolvePluginRoot(
        fs,
        bundlePath,
        flavor: flavor,
      );
      if (root == null) continue;

      final manifest = await CliPluginLayout.readManifest(fs, root, flavor: flavor);
      final pluginName = manifest?.name ?? entry.name;
      final version = manifest?.version ?? '0.0.0';

      final catalogPlugin = _matchCatalogPlugin(
        catalog: catalog,
        enabledById: enabledById,
        bundleDirName: entry.name,
        manifestName: pluginName,
      );

      final marketplaceKey = catalogPlugin?.marketplaceName ?? _localMarketplaceName;
      final cliPluginName = await _resolveCliPluginName(
        pluginsDir: fs.pathContext.join(configDir, 'plugins'),
        marketplaceKey: marketplaceKey,
        manifestName: pluginName,
        catalogPlugin: catalogPlugin,
        teampilotRoot: teampilotRoot,
      );
      final pluginId = '$cliPluginName@$marketplaceKey';
      enabledPlugins[pluginId] = true;
      installedV2[pluginId] = [
        {
          'scope': 'user',
          'installPath': root,
          'version': catalogPlugin?.version ?? version,
          'installedAt': _isoNow(),
        },
      ];

      if (marketplaceKey == _localMarketplaceName) {
        localMarketplacePlugins.add({
          'name': pluginName,
          'source': './$pluginName',
          'version': catalogPlugin?.version ?? version,
        });
      }
    }

    if (enabledPlugins.isEmpty) return;

    final pluginsDir = fs.pathContext.join(configDir, 'plugins');
    await fs.ensureDir(pluginsDir);
    await fs.atomicWrite(
      fs.pathContext.join(pluginsDir, _installedPluginsFileName),
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'plugins': installedV2,
      }),
    );

    await _writeKnownMarketplaces(
      pluginsDir: pluginsDir,
      flavor: flavor,
      catalog: catalog,
      enabledIds: enabledIds,
      localPlugins: localMarketplacePlugins,
    );

    await _mergeEnabledPluginsIntoSettings(
      configDir: configDir,
      tool: tool,
      enabledPlugins: enabledPlugins,
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
  }) async {
    final entries = await _readMarketplacePluginEntries(
      pluginsDir: pluginsDir,
      marketplaceKey: marketplaceKey,
      catalogPlugin: catalogPlugin,
      teampilotRoot: teampilotRoot,
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
  }) async {
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
        return (root['plugins'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, Object?>())
            .toList();
      } catch (_) {
        continue;
      }
    }
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

  Future<void> _writeKnownMarketplaces({
    required String pluginsDir,
    required CliPluginManifestFlavor flavor,
    required List<Plugin> catalog,
    required List<String> enabledIds,
    required List<Map<String, Object?>> localPlugins,
  }) async {
    final marketplaces = await _marketplaceCatalog.loadMarketplaces();
    final byName = {for (final m in marketplaces) m.name: m};
    final now = _isoNow();
    final known = <String, Map<String, Object?>>{};

    final enabled = enabledIds.isEmpty
        ? catalog
        : catalog.where((p) => enabledIds.contains(p.id));

    for (final plugin in enabled) {
      final name = plugin.marketplaceName;
      if (name == null || name.isEmpty || known.containsKey(name)) continue;
      final marketplace = byName[name];
      if (marketplace == null) continue;

      final teampilotCache = fs.pathContext.join(
        teampilotRoot,
        'plugin-marketplace-cache',
        marketplace.owner,
        '${marketplace.name}@${marketplace.branch}',
      );
      if (!(await fs.stat(teampilotCache)).isDirectory) continue;

      final cliInstallLocation = await _materializeMarketplaceForCli(
        pluginsDir: pluginsDir,
        marketplaceName: name,
        teampilotCacheDir: teampilotCache,
        flavor: flavor,
      );
      if (cliInstallLocation == null) continue;

      // Use directory source so the CLI reads installLocation only (no re-clone).
      known[name] = {
        'source': {
          'source': 'directory',
          'path': cliInstallLocation,
        },
        'installLocation': cliInstallLocation,
        'lastUpdated': now,
      };
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

    if (known.isEmpty) return;

    await fs.atomicWrite(
      fs.pathContext.join(pluginsDir, _knownMarketplacesFileName),
      const JsonEncoder.withIndent('  ').convert(known),
    );
  }

  /// Copies TeamPilot's git cache into `{CONFIG_DIR}/plugins/marketplaces/<name>/`.
  ///
  /// Claude Code expects marketplace data under the session plugins tree, not
  /// under `plugin-marketplace-cache`. FlashskyAI additionally needs
  /// `.flashskyai-plugin/marketplace.json` beside `.claude-plugin/`.
  Future<String?> _materializeMarketplaceForCli({
    required String pluginsDir,
    required String marketplaceName,
    required String teampilotCacheDir,
    required CliPluginManifestFlavor flavor,
  }) async {
    final ctx = fs.pathContext;
    final dest = ctx.join(pluginsDir, 'marketplaces', marketplaceName);
    if ((await fs.stat(dest)).exists) {
      await fs.removeRecursive(dest);
    }
    await fs.copyTree(source: teampilotCacheDir, destination: dest);
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
    final text = await fs.readString(path);
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      return (root['plugins'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _isoNow() => DateTime.now().toUtc().toIso8601String();
}
