import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_registry_source.dart';
import '../../models/mcp_server.dart';
import 'mcp_catalog_mapper.dart';
import 'mcp_registry_config_service.dart';
import 'smithery_mcp_auth.dart';
import 'smithery_mcp_service.dart';

/// Resolves catalog listings (Smithery detail) and builds install drafts.
class McpListingInstallService {
  McpListingInstallService({
    McpRegistryConfigService? registryConfig,
    SmitheryMcpService? smithery,
  }) : _registryConfig = registryConfig ?? McpRegistryConfigService(),
       _smithery = smithery ?? SmitheryMcpService();

  final McpRegistryConfigService _registryConfig;
  final SmitheryMcpService _smithery;

  void close() => _smithery.close();

  Future<McpCatalogListing> resolveForInstall(
    McpCatalogListing listing, {
    McpRegistrySourcesConfig? registryConfig,
  }) async {
    if (listing.source != McpCatalogSource.smithery) return listing;
    final qn = listing.smitheryQualifiedName;
    if (qn == null || qn.isEmpty) return listing;

    try {
      final config = registryConfig ?? await _registryConfig.load();
      final smithery = config.byKind(McpRegistrySourceKind.smithery);
      final baseUrl =
          smithery?.baseUrl ??
          McpRegistrySourceConfig.defaultBaseUrl(
            McpRegistrySourceKind.smithery,
          );
      final detail = await _smithery.fetchServerDetail(
        qn,
        baseUrl: baseUrl,
        apiToken: smithery?.apiToken,
      );
      if (detail != null) {
        return McpCatalogMapper.applySmitheryDetail(listing, detail);
      }
    } catch (_) {
      // Keep gateway URL from list row.
    }
    return listing;
  }

  Future<McpServer> draftFromListing(
    McpCatalogListing listing, {
    required int now,
  }) async {
    final McpRegistrySourcesConfig? config =
        listing.source == McpCatalogSource.smithery
        ? await _registryConfig.load()
        : null;
    final resolved = await resolveForInstall(
      listing,
      registryConfig: config,
    );
    var draft = McpCatalogMapper.draftFromListing(resolved, now: now);
    if (resolved.source == McpCatalogSource.smithery && config != null) {
      final token = config.byKind(McpRegistrySourceKind.smithery)?.apiToken;
      draft = draft.copyWith(
        server: SmitheryMcpAuth.applyCatalogBearer(draft.server, token),
      );
    }
    return draft;
  }
}
