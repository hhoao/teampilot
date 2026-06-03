import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// A discovery/favorites card for one public team.
class TeamHubCard extends StatelessWidget {
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

  static const _touchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: workspaceCardDecoration(cs, radius: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.prominent.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: _touchTarget,
                    minHeight: _touchTarget,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: favorited ? cs.primary : cs.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: onToggleFavorite,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                team.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.body.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _Chip(
                  label:
                      '${team.members.length} ${context.l10n.teamHubMembersLabel}',
                ),
                _Chip(
                  label:
                      '${team.skillDeps.length} ${context.l10n.teamHubSkillsLabel}',
                ),
                if (team.category.isNotEmpty) _Chip(label: team.category),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: styles.caption.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// Empty-state block (mirrors SkillEmptyBlock).
class TeamHubEmptyBlock extends StatelessWidget {
  const TeamHubEmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: styles.prominent.copyWith(color: cs.onSurface)),
          const SizedBox(height: 6),
          Text(hint, style: styles.body.copyWith(color: cs.onSurfaceVariant)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
