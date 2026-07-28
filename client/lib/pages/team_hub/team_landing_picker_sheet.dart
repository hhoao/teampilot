import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../services/team/team_landing_recent_store.dart';
import '../../services/team/team_landing_selection.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

import 'team_hub_cards.dart';
import 'team_hub_clone_feedback.dart';
import 'team_hub_detail_overlay.dart';
import 'team_hub_visuals.dart';
import 'team_landing_catalog.dart';

/// Landing team picker — returns the selected local [teamId], or `null`.
Future<String?> showTeamLandingPickerSheet(
  BuildContext context, {
  String? selectedTeamId,
  Future<void> Function(String teamId)? touchRecent,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => TeamLandingPickerDialog(
      selectedTeamId: selectedTeamId,
      touchRecent: touchRecent,
    ),
  );
}

/// Team Hub–style dialog: My Teams + discovery → detail → Confirm.
class TeamLandingPickerDialog extends StatefulWidget {
  const TeamLandingPickerDialog({
    this.selectedTeamId,
    this.touchRecent,
    super.key,
  });

  final String? selectedTeamId;

  /// Defaults to [TeamLandingRecentStore.touch].
  final Future<void> Function(String teamId)? touchRecent;

  @override
  State<TeamLandingPickerDialog> createState() =>
      _TeamLandingPickerDialogState();
}

class _TeamLandingPickerDialogState extends State<TeamLandingPickerDialog> {
  TeamLandingEntry? _detail;
  TeamLandingSourceFilter _sourceFilter = TeamLandingSourceFilter.all;
  String _search = '';
  bool _favoritesOnly = false;
  String? _category;
  bool _confirming = false;

  TeamLandingSelection get _selection => TeamLandingSelection(
    cloneTeam: (team) => context.read<TeamHubCubit>().clone(team),
    touchRecent:
        widget.touchRecent ?? TeamLandingRecentStore().touch,
  );

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TeamHubCubit>();
    if (cubit.state.allTeams.isEmpty &&
        cubit.state.status != TeamHubLoadStatus.loading) {
      unawaited(cubit.load());
    }
  }

  Future<void> _confirmLocal(TeamProfile team) async {
    if (_confirming) return;
    setState(() => _confirming = true);
    final l10n = context.l10n;
    try {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final result = await _selection.resolveLocal(
        teamId: team.id,
        teams: teams,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result.teamId);
    } on TeamLandingSelectionException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    }
  }

  Future<void> _confirmHub(DiscoverableTeam team) async {
    if (_confirming) return;
    setState(() => _confirming = true);
    final l10n = context.l10n;
    try {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final result = await _selection.resolveHub(team: team, teams: teams);
      if (!mounted) return;
      final clone = result.cloneResult;
      if (clone != null) {
        AppToast.show(
          context,
          message: teamHubCloneToastMessage(
            l10n,
            teamName: team.name,
            result: clone,
          ),
          variant: teamHubCloneToastIsWarning(clone)
              ? TpToastVariant.warning
              : TpToastVariant.success,
        );
      }
      Navigator.of(context).pop(result.teamId);
    } on TeamLandingSelectionException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return PopScope(
      canPop: _detail == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_detail != null) {
          setState(() => _detail = null);
        }
      },
      child: TpDialog(
        maxWidth: 960,
        maxHeight: maxHeight,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SizedBox(
          height: maxHeight - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.teamHubTitle),
              const SizedBox(height: 8),
              Expanded(
                child: BlocConsumer<TeamHubCubit, TeamHubState>(
                  listenWhen: (a, b) =>
                      a.errorMessage != b.errorMessage &&
                      b.errorMessage != null,
                  listener: (context, state) {
                    if (state.errorMessage == null) return;
                    AppToast.show(
                      context,
                      message: context.l10n.teamHubLoadError,
                      variant: TpToastVariant.error,
                    );
                    context.read<TeamHubCubit>().clearError();
                  },
                  builder: (context, hubState) {
                    final launchState =
                        context.watch<LaunchProfileCubit>().state;
                    final detail = _detail;
                    if (detail is TeamLandingLocalEntry) {
                      return _LocalTeamDetailOverlay(
                        team: detail.team,
                        confirming: _confirming,
                        inset: 12,
                        onBack: () => setState(() => _detail = null),
                        onConfirm: () => _confirmLocal(detail.team),
                      );
                    }
                    if (detail is TeamLandingHubEntry) {
                      return TeamHubDetailOverlay(
                        key: ValueKey(detail.team.key),
                        team: detail.team,
                        cloning: _confirming ||
                            hubState.cloningKeys.contains(detail.team.key),
                        installedDepIds: hubState.installedDepIds,
                        pickerMode: true,
                        alreadyAdded: detail.localTeamId != null,
                        inset: 12,
                        onBack: () => setState(() => _detail = null),
                        onClone: () {},
                        onConfirm: () => _confirmHub(detail.team),
                      );
                    }
                    return _PickerCatalogBody(
                      hubState: hubState,
                      localTeams: launchState.teams,
                      sourceFilter: _sourceFilter,
                      search: _search,
                      favoritesOnly: _favoritesOnly,
                      category: _category,
                      selectedTeamId: widget.selectedTeamId,
                      onSourceFilter: (f) =>
                          setState(() => _sourceFilter = f),
                      onSearch: (q) => setState(() => _search = q),
                      onFavoritesOnly: (v) =>
                          setState(() => _favoritesOnly = v),
                      onCategory: (c) => setState(() => _category = c),
                      onOpen: (entry) => setState(() => _detail = entry),
                      onToggleFavorite: (key) =>
                          context.read<TeamHubCubit>().toggleFavorite(key),
                      onRefresh: () => context
                          .read<TeamHubCubit>()
                          .load(forceRefresh: true),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerCatalogBody extends StatelessWidget {
  const _PickerCatalogBody({
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
        _PickerFilterBar(
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
                              return _LocalTeamCard(
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
                            mainAxisExtent: 186,
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

class _PickerFilterBar extends StatelessWidget {
  const _PickerFilterBar({
    required this.hubState,
    required this.sourceFilter,
    required this.favoritesOnly,
    required this.category,
    required this.onSourceFilter,
    required this.onFavoritesOnly,
    required this.onCategory,
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
      child: Material(
        color: selected ? cs.surfaceContainer : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
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
      ),
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

class _LocalTeamCard extends StatefulWidget {
  const _LocalTeamCard({
    required this.team,
    required this.selected,
    required this.onTap,
  });

  final TeamProfile team;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LocalTeamCard> createState() => _LocalTeamCardState();
}

class _LocalTeamCardState extends State<_LocalTeamCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final team = widget.team;
    final accent = teamAccentColor(team.id, Theme.of(context).brightness);
    final borderColor = widget.selected
        ? cs.primary
        : _hovered
        ? accent.withValues(alpha: 0.55)
        : cs.outlineVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: widget.selected
              ? cs.primary.withValues(alpha: 0.06)
              : cs.workspaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: widget.selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamMonogram(seed: team.id, label: team.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.mdSemiboldColored(cs.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    team.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mutedMd,
                  ),
                ),
                TeamStatChip(
                  icon: Icons.people_alt_outlined,
                  label: l10n.myTeamsMemberCount(team.roster.length),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalTeamDetailOverlay extends StatelessWidget {
  const _LocalTeamDetailOverlay({
    required this.team,
    required this.confirming,
    required this.onBack,
    required this.onConfirm,
    this.inset = 12,
  });

  final TeamProfile team;
  final bool confirming;
  final VoidCallback onBack;
  final VoidCallback onConfirm;
  final double inset;

  static const _touchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.all(inset),
      child: TeamHubWorkspaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 18, 0),
              child: TeamHubCardHeader(
                title: team.name,
                leading: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: _touchTarget,
                    minHeight: _touchTarget,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: onBack,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TeamMonogram(
                        seed: team.id,
                        label: team.name,
                        size: 52,
                        radius: 14,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TeamStatChip(
                          icon: Icons.people_alt_outlined,
                          label: l10n.myTeamsMemberCount(team.roster.length),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: confirming ? null : onConfirm,
                        child: Text(l10n.teamHubConfirmSelection),
                      ),
                    ],
                  ),
                  if (team.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(team.description, style: styles.mdRelaxed),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
