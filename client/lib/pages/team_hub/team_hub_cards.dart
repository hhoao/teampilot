import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/workspace_surface_layers.dart';
import 'team_hub_visuals.dart';

/// Bordered detail shell — matches [WorkspaceLibraryCard] (without the outer
/// bottom margin, used inside hub lists rather than library pages).
class TeamHubWorkspaceCard extends StatelessWidget {
  const TeamHubWorkspaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class TeamHubCardHeader extends StatelessWidget {
  const TeamHubCardHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final header = TpCardHeader(title: title, trailing: trailing);
    if (leading == null) return header;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading!,
        const SizedBox(width: 4),
        Expanded(child: header),
      ],
    );
  }
}

/// Fixed four-row discovery card for one public team.
///
/// 1. icon + name + favorite
/// 2. description (2 lines, or localized "无")
/// 3. tags
/// 4. metrics + source (source fixed max width, ellipsis)
class TeamHubCard extends StatefulWidget {
  const TeamHubCard({
    super.key,
    required this.team,
    required this.favorited,
    required this.busy,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final DiscoverableTeam team;
  final bool favorited;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  State<TeamHubCard> createState() => _TeamHubCardState();
}

class _TeamHubCardState extends State<TeamHubCard> {
  static const _touchTarget = 40.0;
  static const _radius = 14.0;
  static const _sourceMaxWidth = 120.0;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final team = widget.team;
    final accent = teamAccentColor(team.key, Theme.of(context).brightness);
    final interactive = !widget.busy;
    final borderColor = _hovered
        ? accent.withValues(alpha: 0.55)
        : cs.outlineVariant;

    final description = team.description.trim();
    final descriptionText = description.isEmpty
        ? l10n.teamHubCardNoDescription
        : description;
    final author = team.author?.trim();
    final sourceLabel = (author != null && author.isNotEmpty)
        ? author
        : team.key;

    final tags = <Widget>[
      TeamStatChip(
        icon: Icons.people_alt_outlined,
        label: '${team.roster.length}',
        tooltip: l10n.teamHubMembersLabel,
      ),
      TeamStatChip(
        icon: Icons.auto_awesome_outlined,
        label: '${team.skillDeps.length}',
        tooltip: l10n.teamHubSkillsLabel,
      ),
      if (team.category.isNotEmpty)
        TeamStatChip(label: team.category, accent: accent),
    ];

    return MouseRegion(
      onEnter: (_) {
        if (widget.busy) return;
        setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(_radius),
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
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TeamMonogram(seed: team.key, label: team.name),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.mdSemiboldColored(cs.onSurface),
                    ),
                  ),
                  _FavoriteButton(
                    favorited: widget.favorited,
                    touchTarget: _touchTarget,
                    onPressed: widget.onToggleFavorite,
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Text(
                descriptionText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.smRelaxedColored(
                  description.isEmpty
                      ? cs.onSurface.withValues(alpha: 0.45)
                      : cs.onSurface.withValues(alpha: 0.78),
                ),
              ),
              SizedBox(height: spacing.sm),
              SizedBox(
                height: 28,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      children: [
                        for (var i = 0; i < tags.length; i++) ...[
                          if (i > 0) SizedBox(width: spacing.xs),
                          tags[i],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TpCatalogMetadataRow(
                      adoption: _metric(
                        icon: Icons.download_outlined,
                        label: l10n.teamsCatalogAdoption,
                        value: team.metrics.adoptionCount?.toString(),
                        missing: l10n.catalogMetricMissingTooltip,
                      ),
                      rating: _metric(
                        icon: Icons.star_outline_rounded,
                        label: l10n.catalogMetricRating,
                        value: team.metrics.rating?.toStringAsFixed(1),
                        missing: l10n.catalogMetricMissingTooltip,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _sourceMaxWidth,
                    ),
                    child: Text(
                      sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: styles.xsColored(
                        cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TpCatalogMetricView _metric({
  required IconData icon,
  required String label,
  required String? value,
  required String missing,
}) => TpCatalogMetricView(
  icon: icon,
  label: label,
  value: value,
  missingValueTooltip: missing,
);

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

/// A compact stat pill: optional leading icon + label. When [accent] is set it
/// renders as a tinted category tag instead of the neutral count style.
class TeamStatChip extends StatelessWidget {
  const TeamStatChip({
    super.key,
    required this.label,
    this.icon,
    this.accent,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final Color? accent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final tint = accent;
    final fg = tint ?? cs.onSurfaceVariant;
    final bg = tint != null
        ? tint.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest.withValues(alpha: 0.7);

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 8 : 9,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: styles.xsSemiboldColored(fg)),
        ],
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
