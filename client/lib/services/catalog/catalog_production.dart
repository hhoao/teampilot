import 'dart:io';

import '../../config/mcp_presets.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_registry_source.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../repositories/plugin_repository.dart';
import '../../repositories/skill_repository.dart';
import '../mcp/mcp_catalog_mapper.dart';
import '../mcp/mcp_discovery_disk_cache_service.dart';
import '../mcp/mcp_listing_install_service.dart';
import '../mcp/mcp_registry_browse_service.dart';
import '../mcp/mcp_registry_config_service.dart';
import '../mcp/smithery_mcp_service.dart';
import '../plugin/plugin_external_fetch_service.dart';
import '../plugin/plugin_repo_disk_cache_service.dart';
import '../plugin/plugin_repo_service.dart';
import '../skill/marketplace/skill_marketplace_source.dart';
import '../skill/registry/skill_registry_config_service.dart';
import '../skill/registry/skill_registry_factory.dart';
import '../skill/registry/skill_registry_source.dart';
import 'catalog_kind.dart';

/// Production search / marketplace install adapters for [CatalogRuntime.assemble].
///
/// Uses registry, browse, cache, and install services — not cubits.
abstract final class CatalogProduction {
  static Future<List<Map<String, Object?>>> searchSkills(
    String query, {
    required SkillRegistryConfigService registryConfig,
    required SkillRepository repository,
  }) async {
    final config = await registryConfig.load();
    final sources = SkillRegistryFactory.build(config, repository: repository);
    final hits = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final source in sources) {
      if (!source.enabled) continue;
      try {
        final page = await source.search(SkillRegistryQuery(query: query));
        for (final entry in page.entries) {
          if (!seen.add(entry.key)) continue;
          hits.add(_skillHit(entry));
        }
      } catch (_) {}
    }
    return hits;
  }

  static Future<List<Map<String, Object?>>> searchPlugins(
    String query, {
    required PluginRepoService repos,
    required PluginRepoDiskCacheService diskCache,
  }) async {
    final q = query.trim().toLowerCase();
    final hits = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final marketplace in await repos.loadMarketplaces()) {
      if (!marketplace.enabled) continue;
      try {
        for (final plugin in await diskCache.discoverablePluginsCached(
          marketplace,
        )) {
          if (q.isNotEmpty &&
              !_containsQuery(q, [
                plugin.key,
                plugin.name,
                plugin.description,
              ])) {
            continue;
          }
          if (!seen.add(plugin.key)) continue;
          hits.add(plugin.toJson());
        }
      } catch (_) {}
    }
    return hits;
  }

  static Future<List<Map<String, Object?>>> searchMcp(
    String query, {
    McpRegistryConfigService? registryConfig,
    McpDiscoveryDiskCacheService? diskCache,
    McpRegistryBrowseService? browse,
    SmitheryMcpService? smithery,
  }) async {
    final q = query.trim().toLowerCase();
    final hits = <Map<String, Object?>>[];
    final seen = <String>{};

    void add(McpCatalogListing listing) {
      if (!seen.add(listing.id)) return;
      if (q.isNotEmpty &&
          !_containsQuery(q, [
            listing.id,
            listing.title,
            listing.description,
          ])) {
        return;
      }
      hits.add({
        'id': listing.id,
        'title': listing.title,
        'description': listing.description,
        'source': listing.source.wireValue,
      });
    }

    for (final preset in mcpPresets(descriptionFor: (_) => '')) {
      add(McpCatalogMapper.fromPreset(preset));
    }

    final cache = diskCache ?? McpDiscoveryDiskCacheService();
    for (final key in [mcpDiscoveryCacheSmithery, mcpDiscoveryCacheOfficial]) {
      try {
        final snap = await cache.read(key);
        if (snap == null) continue;
        for (final item in snap.items) {
          add(item);
        }
      } catch (_) {}
    }

    try {
      final config = await (registryConfig ?? McpRegistryConfigService())
          .load();
      final official = config.byKind(McpRegistrySourceKind.officialRegistry);
      if (official != null && official.enabled) {
        final svc = browse ?? McpRegistryBrowseService();
        try {
          final result = await svc.search(query, baseUrl: official.baseUrl);
          for (final item in result.items) {
            add(item);
          }
        } finally {
          if (browse == null) svc.close();
        }
      }
      final smitheryCfg = config.byKind(McpRegistrySourceKind.smithery);
      if (smitheryCfg != null && smitheryCfg.enabled) {
        final svc = smithery ?? SmitheryMcpService();
        try {
          final result = await svc.search(
            query,
            baseUrl: smitheryCfg.baseUrl,
            apiToken: smitheryCfg.apiToken,
          );
          for (final item in result.items) {
            add(item);
          }
        } finally {
          if (smithery == null) svc.close();
        }
      }
    } catch (_) {}
    return hits;
  }

  static Future<McpServer> draftFromListing(
    String listingId, {
    McpListingInstallService? listingInstall,
    McpRegistryConfigService? registryConfig,
    McpDiscoveryDiskCacheService? diskCache,
  }) async {
    final listing = await _resolveListing(
      listingId,
      registryConfig: registryConfig,
      diskCache: diskCache,
    );
    if (listing == null) {
      throw CatalogException('not_found', 'MCP listing not found: $listingId');
    }
    final installer = listingInstall ?? McpListingInstallService();
    try {
      return await installer.draftFromListing(
        listing,
        now: DateTime.now().millisecondsSinceEpoch,
      );
    } finally {
      if (listingInstall == null) installer.close();
    }
  }

  static Future<Plugin> installPluginFromDiscovery(
    Map<String, Object?> arguments, {
    required PluginRepository repository,
    PluginRepoDiskCacheService? diskCache,
    PluginExternalFetchService? externalFetch,
  }) async {
    final id = _string(arguments['id']) ?? _string(arguments['key']) ?? '';
    if (id.isEmpty) {
      throw CatalogException(
        'invalid_args',
        'install_plugin requires id or key',
      );
    }
    final cache = diskCache ?? PluginRepoDiskCacheService();
    final fetch = externalFetch ?? PluginExternalFetchService();
    DiscoverablePlugin? match;
    for (final marketplace in await repository.repos.loadMarketplaces()) {
      try {
        for (final plugin in await cache.discoverablePluginsCached(
          marketplace,
        )) {
          if (plugin.key == id ||
              plugin.installedPluginId == id ||
              plugin.name == id) {
            match = plugin;
            break;
          }
        }
      } catch (_) {}
      if (match != null) break;
    }
    if (match == null) {
      throw CatalogException(
        'not_found',
        'Plugin is not installed and no marketplace entry was found: $id',
      );
    }
    if (!match.canInstall) {
      throw CatalogException(
        'install_failed',
        'Plugin "${match.name}" cannot be installed from this marketplace entry.',
      );
    }
    final marketplace = PluginMarketplace(
      owner: match.marketplaceOwner,
      name: match.marketplaceName,
      branch: match.marketplaceBranch,
    );
    final Directory sourceDir;
    if (match.localInstall) {
      final marketDir = await cache.syncMarketplace(marketplace);
      sourceDir = Directory('$marketDir/${match.source}');
    } else {
      sourceDir = await fetch.fetchPluginDirectory(match.externalSource!);
    }
    if (!sourceDir.existsSync()) {
      throw CatalogException(
        'install_failed',
        'Plugin source directory missing: ${sourceDir.path}',
      );
    }
    return repository.install.installFromDirectory(
      sourceDir,
      marketplace: marketplace,
      marketplaceEntryName: match.name,
    );
  }

  static Future<McpCatalogListing?> _resolveListing(
    String listingId, {
    McpRegistryConfigService? registryConfig,
    McpDiscoveryDiskCacheService? diskCache,
  }) async {
    for (final preset in mcpPresets(descriptionFor: (_) => '')) {
      if (preset.id == listingId) {
        return McpCatalogMapper.fromPreset(preset);
      }
    }

    final cache = diskCache ?? McpDiscoveryDiskCacheService();
    for (final key in [mcpDiscoveryCacheSmithery, mcpDiscoveryCacheOfficial]) {
      try {
        final snap = await cache.read(key);
        if (snap == null) continue;
        for (final item in snap.items) {
          if (item.id == listingId || item.smitheryQualifiedName == listingId) {
            return item;
          }
        }
      } catch (_) {}
    }

    try {
      final config = await (registryConfig ?? McpRegistryConfigService())
          .load();
      final official = config.byKind(McpRegistrySourceKind.officialRegistry);
      if (official != null && official.enabled) {
        final svc = McpRegistryBrowseService();
        try {
          final result = await svc.search(listingId, baseUrl: official.baseUrl);
          for (final item in result.items) {
            if (item.id == listingId) return item;
          }
        } finally {
          svc.close();
        }
      }
      final smitheryCfg = config.byKind(McpRegistrySourceKind.smithery);
      if (smitheryCfg != null && smitheryCfg.enabled) {
        final svc = SmitheryMcpService();
        try {
          final result = await svc.search(
            listingId,
            baseUrl: smitheryCfg.baseUrl,
            apiToken: smitheryCfg.apiToken,
          );
          for (final item in result.items) {
            if (item.id == listingId ||
                item.smitheryQualifiedName == listingId) {
              return item;
            }
          }
        } finally {
          svc.close();
        }
      }
    } catch (_) {}
    return null;
  }

  static Map<String, Object?> _skillHit(MarketplaceSkill entry) => {
    'id': entry.key,
    'key': entry.key,
    'name': entry.name,
    'description': entry.description,
    'repoOwner': entry.repoOwner,
    'repoName': entry.repoName,
    'repoBranch': entry.repoBranch,
    if (entry.directory != null) 'directory': entry.directory,
    'githubUrl': entry.githubUrl,
  };

  static bool _containsQuery(String query, List<String> fields) {
    for (final field in fields) {
      if (field.toLowerCase().contains(query)) return true;
    }
    return false;
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
