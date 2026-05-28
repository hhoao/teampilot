import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_server.dart';
import '../../theme/workspace_surface_layers.dart';

class McpWorkspaceCard extends StatelessWidget {
  const McpWorkspaceCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}

class McpCardHeader extends StatelessWidget {
  const McpCardHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: textBase,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class McpInstalledServerCard extends StatelessWidget {
  const McpInstalledServerCard({
    required this.server,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final McpServer server;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = server.server['type']?.toString() ?? 'stdio';
    final command = server.server['command']?.toString() ?? '';
    final url = server.server['url']?.toString() ?? '';
    final description = server.description.trim();
    final homepage = server.homepage.trim();
    final subtitle = description.isNotEmpty
        ? description
        : (server.tags.isNotEmpty
            ? server.tags.join(', ')
            : (url.isNotEmpty ? url : '$type · $command'));

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: busy ? null : onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (homepage.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () async {
                              final uri = Uri.tryParse(homepage);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            child: Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: cs.primary.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.65),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                IconButton(
                  tooltip: context.l10n.mcpEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: context.l10n.delete,
                  icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
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
    final meta = <String>[
      if (listing.useCount != null) '${listing.useCount} uses',
      if (listing.verified) l10n.mcpCatalogVerified,
      if (listing.remote) 'remote',
      ...listing.tags.take(3),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (listing.iconUrl != null && listing.iconUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      listing.iconUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.hub_outlined,
                        size: 36,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onOpenHomepage != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: onOpenHomepage,
                            icon: const Icon(Icons.open_in_new),
                          ),
                      ],
                    ),
                    if (listing.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        listing.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.65),
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta.join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (installed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(
                    l10n.mcpCatalogInstalled,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                )
              else
                FilledButton.tonal(
                  onPressed: listing.canInstall ? onAdd : null,
                  child: Text(l10n.mcpCatalogAdd),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
