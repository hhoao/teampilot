import '../../config/mcp_presets.dart';
import '../../l10n/app_localizations.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../services/mcp/mcp_catalog_mapper.dart';

String mcpPresetDescription(AppLocalizations l10n, String id) => switch (id) {
  'fetch' => l10n.mcpPresetDescFetch,
  'time' => l10n.mcpPresetDescTime,
  'memory' => l10n.mcpPresetDescMemory,
  'sequential-thinking' => l10n.mcpPresetDescSequentialThinking,
  'context7' => l10n.mcpPresetDescContext7,
  _ => '',
};

List<McpCatalogListing> mcpBuiltinListings(AppLocalizations l10n) {
  return mcpPresets(descriptionFor: (id) => mcpPresetDescription(l10n, id))
      .map(McpCatalogMapper.fromPreset)
      .toList();
}

List<McpCatalogListing> filterMcpBuiltinListings(
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
