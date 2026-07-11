import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_hub/team_hub_cards.dart';
import 'expert_hub_visuals.dart';

/// Bordered detail shell — reuses [TeamHubWorkspaceCard] styling.
class ExpertHubWorkspaceCard extends StatelessWidget {
  const ExpertHubWorkspaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TeamHubWorkspaceCard(child: child);
}

class ExpertHubCardHeader extends StatelessWidget {
  const ExpertHubCardHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => TeamHubCardHeader(
    title: title,
    leading: leading,
    trailing: trailing,
  );
}

/// A discovery/favorites card for one public member persona.
class ExpertHubCard extends StatefulWidget {
  const ExpertHubCard({
    super.key,
    required this.member,
    required this.favorited,
    required this.busy,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final DiscoverableMember member;
  final bool favorited;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  State<ExpertHubCard> createState() => _ExpertHubCardState();
}

class _ExpertHubCardState extends State<ExpertHubCard> {
  static const _touchTarget = 40.0;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final member = widget.member;
    final accent = teamAccentColor(member.key, Theme.of(context).brightness);
    final borderColor = _hovered
        ? accent.withValues(alpha: 0.55)
        : cs.outlineVariant;

    return MouseRegion(
      cursor: widget.busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: cs.workspaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.busy ? null : widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TeamMonogram(seed: member.key, label: member.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.mdSemiboldColored(cs.onSurface,),
                          ),
                          if (member.author != null &&
                              member.author!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              member.author!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: styles.mutedXs,
                            ),
                          ],
                        ],
                      ),
                    ),
                    _FavoriteButton(
                      favorited: widget.favorited,
                      touchTarget: _touchTarget,
                      onPressed: widget.onToggleFavorite,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    member.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mutedMd,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ExpertSourceBadge(source: member.source, accent: accent),
                    if (member.member.capabilities.isNotEmpty)
                      TeamStatChip(
                        icon: Icons.psychology_outlined,
                        label: '${member.member.capabilities.length}',
                        tooltip: context.l10n.expertHubCapabilities,
                      ),
                    if (member.skillDeps.isNotEmpty)
                      TeamStatChip(
                        icon: Icons.auto_awesome_outlined,
                        label: '${member.skillDeps.length}',
                        tooltip: context.l10n.teamHubSkillsLabel,
                      ),
                    if (member.pluginDeps.isNotEmpty)
                      TeamStatChip(
                        icon: Icons.extension_outlined,
                        label: '${member.pluginDeps.length}',
                        tooltip: context.l10n.teamHubPluginsLabel,
                      ),
                    if (member.mcpDeps.isNotEmpty)
                      TeamStatChip(
                        icon: Icons.cable_outlined,
                        label: '${member.mcpDeps.length}',
                        tooltip: context.l10n.teamHubMcpLabel,
                      ),
                    if (member.category.isNotEmpty)
                      TeamStatChip(label: member.category, accent: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExpertSourceBadge extends StatelessWidget {
  const ExpertSourceBadge({super.key, required this.source, this.accent});

  final ExpertMemberSource source;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = switch (source) {
      ExpertMemberSource.builtin => l10n.expertHubSourceBuiltin,
      ExpertMemberSource.registry => l10n.expertHubSourceRegistry,
      ExpertMemberSource.local => l10n.expertHubSourceLocal,
      ExpertMemberSource.teamExtract => l10n.expertHubSourceTeamExtract,
    };
    return TeamStatChip(label: label, accent: accent);
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.favorited,
    required this.touchTarget,
    required this.onPressed,
  });

  final bool favorited;
  final double touchTarget;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      constraints: BoxConstraints(
        minWidth: touchTarget,
        minHeight: touchTarget,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        favorited ? Icons.star_rounded : Icons.star_outline_rounded,
        color: favorited ? cs.primary : cs.onSurfaceVariant,
        size: 20,
      ),
      onPressed: onPressed,
    );
  }
}
