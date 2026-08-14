import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../utils/debounce/debounce.dart';
import 'skill_discovery_helpers.dart';
import 'skill_discovery_repos_panel.dart';
import 'skill_marketplace_panel.dart';
import 'skill_management_cards.dart';
import 'skill_source_toggle.dart';

class SkillDiscoverySection extends StatefulWidget {
  const SkillDiscoverySection({super.key, required this.onGoRepos});

  final VoidCallback onGoRepos;

  @override
  State<SkillDiscoverySection> createState() => SkillDiscoverySectionState();
}

class SkillDiscoverySectionState extends State<SkillDiscoverySection> {
  SkillSearchSource _source = SkillSearchSource.repos;
  String? _marketplaceId;
  String _searchQuery = '';
  String _filterRepo = 'all';
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SkillCubit>().ensureDiscoveryLoaded();
    });
  }

  @override
  void dispose() {
    Debounces.cancel('skill_discovery_search');
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Debounces.debounce(
      'skill_discovery_search',
      const Duration(milliseconds: 400),
      () {
        if (!mounted) return;
        setState(() => _searchQuery = value);
      },
    );
  }

  void _reconcileRepoFilter(SkillState state) {
    final choices = skillDiscoveryRepoFilterChoices(
      state.repos,
      state.discoverable,
      context.l10n,
    );
    final effective = resolveSkillDiscoveryRepoFilter(_filterRepo, choices);
    if (effective != _filterRepo && mounted) {
      setState(() => _filterRepo = effective);
    }
  }

  void _onSourceChanged(SkillSearchSource next, String? id) {
    setState(() {
      _source = next;
      if (next == SkillSearchSource.marketplace) {
        final marketplaces = context.read<SkillCubit>().marketplaces;
        _marketplaceId =
            id ?? (marketplaces.isNotEmpty ? marketplaces.first.id : null);
      } else {
        _marketplaceId = null;
      }
    });
  }

  SkillMarketplaceSource? _selectedMarketplace(
    List<SkillMarketplaceSource> all,
  ) {
    if (_source != SkillSearchSource.marketplace) return null;
    final id = _marketplaceId;
    if (id == null) return null;
    for (final mp in all) {
      if (mp.id == id) return mp;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final marketplaces = context.read<SkillCubit>().marketplaces;
    final marketplace = _selectedMarketplace(marketplaces);
    return BlocListener<SkillCubit, SkillState>(
      listenWhen: (previous, current) =>
          previous.repos != current.repos ||
          previous.discoverable != current.discoverable,
      listener: (context, state) => _reconcileRepoFilter(state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkillManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SkillDiscoverySourceRow(
                  source: _source,
                  marketplaceId: _marketplaceId,
                  marketplaces: marketplaces,
                  onSourceChanged: _onSourceChanged,
                ),
                if (_source == SkillSearchSource.repos) ...[
                  const _SkillDiscoverySyncBanner(),
                  const SizedBox(height: 14),
                  SkillDiscoveryReposFilters(
                    filterRepo: _filterRepo,
                    filterStatus: _filterStatus,
                    onSearchChanged: _onSearchChanged,
                    onFilterRepoChanged: (v) => setState(() => _filterRepo = v),
                    onFilterStatusChanged: (v) =>
                        setState(() => _filterStatus = v),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: marketplace != null
                ? SkillMarketplacePanel(source: marketplace)
                : SkillDiscoveryReposBody(
                    filterRepo: _filterRepo,
                    filterStatus: _filterStatus,
                    searchQuery: _searchQuery,
                    onGoRepos: widget.onGoRepos,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SkillDiscoverySourceRow extends StatelessWidget {
  const _SkillDiscoverySourceRow({
    required this.source,
    required this.marketplaces,
    required this.marketplaceId,
    required this.onSourceChanged,
  });

  final SkillSearchSource source;
  final List<SkillMarketplaceSource> marketplaces;
  final String? marketplaceId;
  final void Function(SkillSearchSource next, String? id) onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        SkillSourceToggle(
          label: l10n.skillsSourceRepos,
          selected: source == SkillSearchSource.repos,
          onTap: () => onSourceChanged(SkillSearchSource.repos, null),
        ),
        for (final mp in marketplaces) ...[
          const SizedBox(width: 8),
          SkillSourceToggle(
            label: mp.label,
            selected:
                source == SkillSearchSource.marketplace &&
                marketplaceId == mp.id,
            onTap: () => onSourceChanged(SkillSearchSource.marketplace, mp.id),
          ),
        ],
        const Spacer(),
        if (source == SkillSearchSource.repos)
          const _SkillDiscoveryRefreshButton(),
      ],
    );
  }
}

class _SkillDiscoveryRefreshButton extends StatelessWidget {
  const _SkillDiscoveryRefreshButton();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<SkillCubit, SkillState, SkillDiscoverySyncSlice>(
      selector: (state) => (
        discoveryLoading: state.discoveryLoading,
        repoSyncingKeys: state.repoSyncingKeys,
      ),
      builder: (context, sync) {
        final syncing =
            sync.discoveryLoading || sync.repoSyncingKeys.isNotEmpty;
        return IconButton(
          tooltip: l10n.skillsCheckUpdates,
          onPressed: syncing
              ? null
              : () => context.read<SkillCubit>().ensureDiscoveryLoaded(
                  force: true,
                ),
          icon: syncing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.refresh, size: context.tpIconSizes.md),
        );
      },
    );
  }
}

class _SkillDiscoverySyncBanner extends StatelessWidget {
  const _SkillDiscoverySyncBanner();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SkillCubit, SkillState, Set<String>>(
      selector: (state) => state.repoSyncingKeys,
      builder: (context, syncingKeys) {
        if (syncingKeys.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.skillsDiscoverySyncing,
                  style: TpTextStyles.of(context).sm,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
