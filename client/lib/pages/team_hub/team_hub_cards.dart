import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'team_hub_visuals.dart';

/// Bordered detail shell — matches [McpWorkspaceCard] / [SkillManagementCard].
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
    final header = ManagementCardHeader(title: title, trailing: trailing);
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

/// A discovery/favorites card for one public team.
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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final team = widget.team;
    final accent = teamAccentColor(team.key, Theme.of(context).brightness);
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
                    TeamMonogram(seed: team.key, label: team.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.bodyStrong.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                          if (team.author != null &&
                              team.author!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              team.author!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: styles.mutedCaption,
                            ),
                          ],
                        ],
                      ),
                    ),
                    _FavoriteButton(
                      favorited: widget.favorited,
                      touchTarget: _touchTarget,
                      accent: accent,
                      onPressed: widget.onToggleFavorite,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    team.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mutedBody,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TeamStatChip(
                      icon: Icons.people_alt_outlined,
                      label: '${team.members.length}',
                      tooltip: context.l10n.teamHubMembersLabel,
                    ),
                    TeamStatChip(
                      icon: Icons.auto_awesome_outlined,
                      label: '${team.skillDeps.length}',
                      tooltip: context.l10n.teamHubSkillsLabel,
                    ),
                    if (team.category.isNotEmpty)
                      TeamStatChip(label: team.category, accent: accent),
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

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.favorited,
    required this.touchTarget,
    required this.accent,
    required this.onPressed,
  });

  final bool favorited;
  final double touchTarget;
  final Color accent;
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
    final styles = AppTextStyles.of(context);
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
          Text(
            label,
            style: styles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
