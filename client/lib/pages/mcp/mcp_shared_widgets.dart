import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_server.dart';
import '../../widgets/github_details_button.dart';
import '../../theme/workspace_surface_layers.dart';

class McpInstalledServerRow extends StatelessWidget {
  const McpInstalledServerRow({
    required this.server,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    this.oauthAuthenticated,
    this.onOAuthConnect,
    super.key,
  });

  final McpServer server;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;
  final bool? oauthAuthenticated;
  final VoidCallback? onOAuthConnect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textBase = cs.onSurface;
    final type = server.server['type']?.toString() ?? 'stdio';
    final command = server.server['command']?.toString() ?? '';
    final url = server.server['url']?.toString() ?? '';
    final description = server.description.trim();
    final typeLabel = url.isNotEmpty ? url : '$type · $command';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTextStyles.of(context)
                              .mdSemiboldColored(textBase),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTextStyles.of(context)
                              .xsColored(textBase.withValues(alpha: 0.5)),
                        ),
                      ),
                      if (oauthAuthenticated == false) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.mcpOAuthStatusNeedsAuth,
                            style: TpTextStyles.of(context)
                                .xsBoldColored(const Color(0xFFB45309)),
                          ),
                        ),
                      ],
                      if (oauthAuthenticated == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.mcpOAuthStatusConnected,
                            style: TpTextStyles.of(context)
                                .xsBoldColored(cs.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(context)
                          .smColored(textBase.withValues(alpha: 0.6)),
                    ),
                  ],
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (onOAuthConnect != null && oauthAuthenticated != true)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: OutlinedButton(
                  onPressed: busy ? null : onOAuthConnect,
                  child: Text(l10n.mcpOAuthConnectAction),
                ),
              ),
            if (server.homepage.trim().isNotEmpty)
              IconButton(
                tooltip: l10n.mcpOpenHomepage,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: busy
                    ? null
                    : () => openGithubBrowseUrl(server.homepage.trim()),
                icon: Icon(Icons.open_in_new),
              ),
            const SizedBox(width: 4),

            IconButton(
              tooltip: l10n.mcpEdit,
              onPressed: busy ? null : onEdit,
              icon: Icon(Icons.edit_outlined, size: context.tpIconSizes.md),
            ),
            IconButton(
              tooltip: l10n.delete,
              onPressed: busy ? null : onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: context.tpIconSizes.md,
                color: cs.error,
              ),
            ),
            Switch(
              value: server.enabled,
              onChanged: busy ? null : onToggleEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

class McpCatalogListingTile extends StatelessWidget {
  const McpCatalogListingTile({
    required this.listing,
    required this.installed,
    required this.busy,
    required this.onAdd,
    required this.onOpenHomepage,
    super.key,
  });

  final McpCatalogListing listing;
  final bool installed;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback? onOpenHomepage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final metrics = listing.metrics;
    final adoption = metrics.adoptionCount ?? listing.useCount;
    final tagLabels = <String>[
      if (listing.verified) l10n.mcpCatalogVerified,
      if (listing.remote) 'remote',
      ...listing.tags.take(3),
    ];

    return TpCatalogListCard(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _McpCatalogIcon(listing: listing),
      ),
      title: listing.title,
      source: _mcpCatalogSourceLabel(listing.source),
      description: listing.description,
      emptyDescription: l10n.mcpCatalogCardNoDescription,
      tags: [for (final label in tagLabels) TpCatalogTagChip(label: label)],
      adoption: TpCatalogMetricView(
        icon: Icons.trending_up_outlined,
        label: l10n.mcpCatalogAdoption,
        value: adoption?.toString(),
        missingValueTooltip: l10n.catalogMetricMissingTooltip,
      ),
      rating: TpCatalogMetricView(
        icon: Icons.star_outline,
        label: l10n.catalogMetricRating,
        value: metrics.rating?.toStringAsFixed(1),
        missingValueTooltip: l10n.catalogMetricMissingTooltip,
      ),
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOpenHomepage != null)
            IconButton(
              tooltip: l10n.mcpOpenHomepage,
              visualDensity: VisualDensity.compact,
              iconSize: context.tpIconSizes.md,
              onPressed: onOpenHomepage,
              icon: const Icon(Icons.open_in_new),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (installed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.mcpCatalogInstalled,
                style: styles.smSemiboldColored(cs.primary),
              ),
            )
          else
            FilledButton.tonal(
              onPressed: listing.canInstall ? onAdd : null,
              child: Text(l10n.mcpCatalogAdd),
            ),
        ],
      ),
    );
  }
}

class _McpCatalogIcon extends StatelessWidget {
  const _McpCatalogIcon({required this.listing});

  final McpCatalogListing listing;

  static const double _size = TpCatalogListCard.leadingSize;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.45,
      ),
      child: Center(
        child: Icon(
          Icons.hub_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );

    final url = listing.iconUrl;
    if (url == null || url.isEmpty) return placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: (_, __) => placeholder(),
      errorWidget: (_, __, ___) => placeholder(),
    );
  }
}

String _mcpCatalogSourceLabel(McpCatalogSource source) => switch (source) {
  McpCatalogSource.builtin => 'Built-in',
  McpCatalogSource.smithery => 'Smithery',
  McpCatalogSource.officialRegistry => 'Official MCP Registry',
};
