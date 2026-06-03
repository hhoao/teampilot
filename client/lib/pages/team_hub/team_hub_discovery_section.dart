import 'package:flutter/material.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import 'team_hub_cards.dart';

class TeamHubDiscoverySection extends StatelessWidget {
  const TeamHubDiscoverySection({
    super.key,
    required this.cubit,
    required this.onOpen,
  });

  final TeamHubCubit cubit;
  final void Function(DiscoverableTeam) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final state = cubit.state;
    final teams = cubit.visibleTeams;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 200, child: _CategoryRail(cubit: cubit)),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: l10n.teamHubSearchHint,
                          prefixIcon: const Icon(
                            Icons.search,
                            size: AppIconSizes.md,
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                        ),
                        onChanged: cubit.setSearch,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 180,
                      child: AppDropdownField<TeamSort>(
                        items: const [TeamSort.name, TeamSort.updated],
                        initialItem: state.sort,
                        itemLabel: (s) => switch (s) {
                          TeamSort.name => l10n.teamHubSortName,
                          TeamSort.updated => l10n.teamHubSortUpdated,
                        },
                        onChanged: (s) =>
                            s == null ? null : cubit.setSort(s),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _grid(context, state, teams)),
            ],
          ),
        ),
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
      return Padding(
        padding: const EdgeInsets.all(24),
        child: TeamHubEmptyBlock(
          icon: isError
              ? Icons.cloud_off_outlined
              : Icons.travel_explore_outlined,
          title: isError ? l10n.teamHubLoadError : l10n.teamHubEmptyTitle,
          hint: isError ? '' : l10n.teamHubEmptyHint,
          actionLabel: l10n.teamHubRefresh,
          onAction: () => cubit.load(forceRefresh: true),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 176,
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

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.cubit});
  final TeamHubCubit cubit;

  static const _touchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final state = cubit.state;
    final selected = state.selectedCategory;
    final counts = state.categoryCounts;

    Widget row(String label, String? value, int count) {
      final active = selected == value;
      return InkWell(
        onTap: () => cubit.setCategory(value),
        child: Container(
          constraints: const BoxConstraints(minHeight: _touchTarget),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: active ? cs.primary.withValues(alpha: 0.12) : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.body.copyWith(
                    color: active ? cs.primary : cs.onSurface,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: styles.caption.copyWith(
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        row(l10n.teamHubCategoryAll, null, state.allTeams.length),
        for (final c in state.categories) row(c, c, counts[c] ?? 0),
      ],
    );
  }
}
