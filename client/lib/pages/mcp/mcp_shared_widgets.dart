import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_server.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/github_details_button.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

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
    return ManagementCardHeader(
      title: title,
      trailing: trailing,
      crossAxisAlignment: CrossAxisAlignment.center,
    );
  }
}

class McpEmptyBlock extends StatelessWidget {
  const McpEmptyBlock({
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: AppIconSizes.md, color: textBase.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTextStyles.of(context).bodyStrong.copyWith(
              color: textBase,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: AppTextStyles.of(context).bodySmall.copyWith(
              color: textBase.withValues(alpha: 0.55),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
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
                          style: AppTextStyles.of(context).bodyStrong.copyWith(
                            color: textBase,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(context).caption.copyWith(
                            color: textBase.withValues(alpha: 0.5),
                          ),
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
                            style: AppTextStyles.of(context).caption.copyWith(
                              color: const Color(0xFFB45309),
                              fontWeight: FontWeight.w700,
                            ),
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
                            style: AppTextStyles.of(context).caption.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
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
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: textBase.withValues(alpha: 0.6),
                      ),
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
                iconSize: AppIconSizes.md,
                onPressed: busy
                    ? null
                    : () => openGithubBrowseUrl(server.homepage.trim()),
                icon: const Icon(Icons.open_in_new),
              ),
            const SizedBox(width: 4),

            IconButton(
              tooltip: l10n.mcpEdit,
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit_outlined, size: AppIconSizes.md),
            ),
            IconButton(
              tooltip: l10n.delete,
              onPressed: busy ? null : onDelete,
              icon: Icon(Icons.delete_outline, size: AppIconSizes.md, color: cs.error),
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
    final meta = <String>[
      if (listing.useCount != null) '${listing.useCount} uses',
      if (listing.verified) l10n.mcpCatalogVerified,
      if (listing.remote) 'remote',
      ...listing.tags.take(3),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
              if (listing.iconUrl != null && listing.iconUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      listing.iconUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.hub_outlined,
                        size: AppIconSizes.md,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listing.title,
                            style: AppTextStyles.of(context).bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onOpenHomepage != null)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            visualDensity: VisualDensity.compact,
                            iconSize: AppIconSizes.md,
                            tooltip: l10n.mcpOpenHomepage,
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
                        style: AppTextStyles.of(context).bodySmall.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta.join(' · '),
                        style: AppTextStyles.of(context).caption.copyWith(
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.mcpCatalogInstalled,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
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
    );
  }
}
