import 'package:flutter/material.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import 'package:shared_ui/shared_ui.dart';
import 'team_hub_cards.dart';

/// Single-page hub body: a toolbar (search + sort), an inline filter-chip bar
/// (favorites toggle + category single-select), then the team grid. No
/// sub-navigation — every refinement is an in-page filter.
class TeamHubBody extends StatelessWidget {
  const TeamHubBody({
    super.key,
    required this.cubit,
    required this.onOpen,
    this.inset = 28,
  });

  final TeamHubCubit cubit;
  final void Function(DiscoverableTeam) onOpen;

  /// Horizontal page inset (tighter on Android).
  final double inset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = cubit.state;
    final teams = cubit.visibleTeams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 18, inset, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Search + fixed 180 sort + refresh exceeds narrow phone widths.
              final stackControls = constraints.maxWidth < 460;
              final searchField = TextField(
                decoration: InputDecoration(
                  hintText: l10n.teamHubSearchHint,
                  prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                onChanged: cubit.setSearch,
              );
              final sortSelect = TpSelect<TeamSort>(
                items: const [TeamSort.name, TeamSort.updated],
                initialItem: state.sort,
                itemLabel: (s) => switch (s) {
                  TeamSort.name => l10n.teamHubSortName,
                  TeamSort.updated => l10n.teamHubSortUpdated,
                },
                onChanged: (s) => s == null ? null : cubit.setSort(s),
              );
              final refreshButton = IconButton(
                key: const Key('team-hub-refresh'),
                tooltip: l10n.teamHubRefresh,
                onPressed: state.refreshing
                    ? null
                    : () => cubit.load(forceRefresh: true),
                icon: state.refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh, size: context.tpIconSizes.md),
              );
              if (stackControls) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: sortSelect),
                        const SizedBox(width: 4),
                        refreshButton,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: sortSelect),
                  const SizedBox(width: 4),
                  refreshButton,
                ],
              );
            },
          ),
        ),
        _FilterBar(cubit: cubit, inset: inset),
        Expanded(child: _grid(context, state, teams)),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    TeamHubState state,
    List<DiscoverableTeam> teams,
  ) {
    final l10n = context.l10n;
    if (state.status == TeamHubLoadStatus.loading && teams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (teams.isEmpty) {
      final isError = state.status == TeamHubLoadStatus.error;
      if (state.favoritesOnly && !isError) {
        return TpEmptyState(
          centered: true,
          icon: Icons.star_outline_rounded,
          title: l10n.teamHubFavoritesEmptyTitle,
          hint: l10n.teamHubFavoritesEmptyHint,
        );
      }
      return Padding(
        padding: EdgeInsets.all(inset),
        child: TpEmptyState(
          centered: true,
          icon: isError
              ? Icons.cloud_off_outlined
              : Icons.travel_explore_outlined,
          title: isError ? l10n.teamHubLoadError : l10n.teamHubEmptyTitle,
          hint: isError ? null : l10n.teamHubEmptyHint,
          actionLabel: l10n.teamHubRefresh,
          onAction: () => cubit.load(forceRefresh: true),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(inset, 4, inset, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 186,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: teams.length,
      itemBuilder: (context, i) {
        final t = teams[i];
        return TeamHubCard(
          team: t,
          favorited: state.favorites.contains(t.key),
          busy: state.cloningKeys.contains(t.key),
          onTap: () => onOpen(t),
          onToggleFavorite: () => cubit.toggleFavorite(t.key),
        );
      },
    );
  }
}

/// Horizontally scrollable filter bar: a favorites toggle, then a single-select
/// category group (All + each category) with counts.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.cubit, required this.inset});

  final TeamHubCubit cubit;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final state = cubit.state;
    final counts = state.categoryCounts;
    final selected = state.selectedCategory;

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
        children: [
          _FilterPill(
            label: l10n.teamHubFavorites,
            icon: state.favoritesOnly
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            selected: state.favoritesOnly,
            onTap: () => cubit.setFavoritesOnly(!state.favoritesOnly),
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
            count: state.allTeams.length,
            selected: selected == null,
            onTap: () => cubit.setCategory(null),
          ),
          for (final c in state.categories)
            _FilterPill(
              label: c,
              count: counts[c] ?? 0,
              selected: selected == c,
              onTap: () => cubit.setCategory(c),
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
              Text(label, style: fg != null ? styles.mdColored(fg) : styles.md),
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
