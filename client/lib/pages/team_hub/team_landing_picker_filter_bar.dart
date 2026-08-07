import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'team_landing_catalog.dart';

/// Source / favorites / category pills for the landing team picker.
class TeamLandingPickerFilterBar extends StatelessWidget {
  const TeamLandingPickerFilterBar({
    required this.hubState,
    required this.sourceFilter,
    required this.favoritesOnly,
    required this.category,
    required this.onSourceFilter,
    required this.onFavoritesOnly,
    required this.onCategory,
    super.key,
  });

  final TeamHubState hubState;
  final TeamLandingSourceFilter sourceFilter;
  final bool favoritesOnly;
  final String? category;
  final ValueChanged<TeamLandingSourceFilter> onSourceFilter;
  final ValueChanged<bool> onFavoritesOnly;
  final ValueChanged<String?> onCategory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final counts = hubState.categoryCounts;

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _FilterPill(
            label: l10n.teamHubCategoryAll,
            selected: sourceFilter == TeamLandingSourceFilter.all,
            onTap: () => onSourceFilter(TeamLandingSourceFilter.all),
          ),
          _FilterPill(
            label: l10n.myTeamsTitle,
            selected: sourceFilter == TeamLandingSourceFilter.mine,
            onTap: () => onSourceFilter(TeamLandingSourceFilter.mine),
          ),
          _FilterPill(
            label: l10n.teamHubDiscovery,
            selected: sourceFilter == TeamLandingSourceFilter.discovery,
            onTap: () => onSourceFilter(TeamLandingSourceFilter.discovery),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          _FilterPill(
            label: l10n.teamHubFavorites,
            icon: favoritesOnly
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            selected: favoritesOnly,
            onTap: () => onFavoritesOnly(!favoritesOnly),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          _FilterPill(
            label: l10n.teamHubCategoryAll,
            count: hubState.allTeams.length,
            selected: category == null,
            onTap: () => onCategory(null),
          ),
          for (final c in hubState.categories)
            _FilterPill(
              label: c,
              count: counts[c] ?? 0,
              selected: category == c,
              onTap: () => onCategory(c),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final fg = selected ? cs.primary : null;
    final border = selected
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TpHover(
        backgroundColor: selected ? cs.surfaceContainer : Colors.transparent,
        shape: TpPressableShape.stadium,
        border: Border.all(color: border),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: fg != null ? styles.mdColored(fg) : styles.md,
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: styles.xsColored(
                    selected
                        ? cs.primary.withValues(alpha: 0.8)
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
