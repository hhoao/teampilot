import '../../cubits/mcp_discovery_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/mcp_catalog_listing.dart';

const mcpDiscoverySourceOrder = <McpDiscoverySource>[
  McpDiscoverySource.all,
  McpDiscoverySource.builtin,
  McpDiscoverySource.smithery,
  McpDiscoverySource.official,
];

String mcpDiscoverySourceLabel(
  AppLocalizations l10n,
  McpDiscoverySource source,
) =>
    switch (source) {
      McpDiscoverySource.all => l10n.mcpDiscoverySourceAll,
      McpDiscoverySource.builtin => l10n.mcpDiscoverySourceBuiltin,
      McpDiscoverySource.smithery => l10n.mcpRegistrySmithery,
      McpDiscoverySource.official => l10n.mcpRegistryOfficial,
    };

bool mcpDiscoveryShowsSearch(McpDiscoverySource source) =>
    source != McpDiscoverySource.builtin;

List<McpCatalogListing> filterMcpRemoteListings(
  List<McpCatalogListing> items,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items
      .where(
        (e) =>
            e.title.toLowerCase().contains(q) ||
            e.id.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q),
      )
      .toList();
}

/// Built-in first, then remote caches; dedupe by [McpCatalogListing.id].
List<McpCatalogListing> mergeMcpDiscoveryAll({
  required List<McpCatalogListing> builtin,
  required List<McpCatalogListing> smithery,
  required List<McpCatalogListing> official,
  required String query,
}) {
  final remote = [
    ...filterMcpRemoteListings(smithery, query),
    ...filterMcpRemoteListings(official, query),
  ];
  final seen = <String>{};
  final merged = <McpCatalogListing>[];
  for (final item in [...builtin, ...remote]) {
    if (seen.add(item.id)) {
      merged.add(item);
    }
  }
  return merged;
}
