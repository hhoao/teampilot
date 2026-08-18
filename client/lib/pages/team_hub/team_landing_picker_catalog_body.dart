import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import 'team_hub_cards.dart';
import 'team_landing_catalog.dart';
import 'team_landing_picker_filter_bar.dart';
import 'team_landing_picker_local_card.dart';

/// Catalog grid for the landing team picker (My Teams + Discovery).
class TeamLandingPickerCatalogBody extends StatelessWidget {
  const TeamLandingPickerCatalogBody({
    required this.hubState,
    required this.localTeams,
    required this.sourceFilter,
    required this.search,
    required this.favoritesOnly,
    required this.category,
    required this.selectedTeamId,
    required this.onSourceFilter,
    required this.onSearch,
    required this.onFavoritesOnly,
    required this.onCategory,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onRefresh,
    super.key,
  });

  final TeamHubState hubState;
  final List<TeamProfile> localTeams;
  final TeamLandingSourceFilter sourceFilter;
  final String search;
  final bool favoritesOnly;
  final String? category;
  final String? selectedTeamId;
  final ValueChanged<TeamLandingSourceFilter> onSourceFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onFavoritesOnly;
  final ValueChanged<String?> onCategory;
  final ValueChanged<TeamLandingEntry> onOpen;
  final ValueChanged<String> onToggleFavorite;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = buildTeamLandingCatalog(
      localTeams: localTeams,
      hubTeams: hubState.allTeams,
      sourceFilter: sourceFilter,
      searchQuery: search,
      favoritesOnly: favoritesOnly,
      favoriteKeys: hubState.favorites,
      category: category,
    );
    final loading = hubState.status == TeamHubLoadStatus.loading &&
        hubState.allTeams.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: l10n.teamHubSearchHint,
              prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onChanged: onSearch,
          ),
        ),
        TeamLandingPickerFilterBar(
          hubState: hubState,
          sourceFilter: sourceFilter,
          favoritesOnly: favoritesOnly,
          category: category,
          onSourceFilter: onSourceFilter,
          onFavoritesOnly: onFavoritesOnly,
          onCategory: onCategory,
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : sections.mine.isEmpty && sections.discovery.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: TpEmptyState(
                    centered: true,
                    icon: hubState.status == TeamHubLoadStatus.error
                        ? Icons.cloud_off_outlined
                        : Icons.travel_explore_outlined,
                    title: hubState.status == TeamHubLoadStatus.error
                        ? l10n.teamHubLoadError
                        : l10n.teamHubEmptyTitle,
                    hint: hubState.status == TeamHubLoadStatus.error
                        ? null
                        : l10n.teamHubEmptyHint,
                    actionLabel: l10n.teamHubRefresh,
                    onAction: onRefresh,
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    if (sections.mine.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionHeader(title: l10n.myTeamsTitle),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 380,
                            mainAxisExtent: 160,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final entry = sections.mine[i];
                              return TeamLandingPickerLocalCard(
                                team: entry.team,
                                selected: entry.team.id == selectedTeamId,
                                onTap: () => onOpen(entry),
                              );
                            },
                            childCount: sections.mine.length,
                          ),
                        ),
                      ),
                    ],
                    if (sections.discovery.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionHeader(title: l10n.teamHubDiscovery),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 380,
                            mainAxisExtent: 420,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final entry = sections.discovery[i];
                              return TeamHubCard(
                                team: entry.team,
                                favorited: hubState.favorites.contains(
                                  entry.team.key,
                                ),
                                busy: hubState.cloningKeys.contains(
                                  entry.team.key,
                                ),
                                onTap: () => onOpen(entry),
                                onToggleFavorite: () =>
                                    onToggleFavorite(entry.team.key),
                              );
                            },
                            childCount: sections.discovery.length,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: styles.mdSemiboldTightSnugColored(cs.onSurface),
      ),
    );
  }
}
