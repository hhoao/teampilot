import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/debounce/debounce.dart';
import 'skill_discovery_helpers.dart';
import 'skill_discovery_repos_panel.dart';
import 'skill_discovery_skills_sh_panel.dart';
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
  String _searchQuery = '';
  String _filterRepo = 'all';
  String _filterStatus = 'all';
  final _skillsShCtl = TextEditingController();

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
    _skillsShCtl.dispose();
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

  @override
  Widget build(BuildContext context) {
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
                  onSourceChanged: (source) => setState(() => _source = source),
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
                ] else ...[
                  const SizedBox(height: 14),
                  SkillDiscoverySkillsShSearchBar(
                    controller: _skillsShCtl,
                    onSearch: context.read<SkillCubit>().searchSkillsSh,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _source == SkillSearchSource.repos
                ? SkillDiscoveryReposBody(
                    filterRepo: _filterRepo,
                    filterStatus: _filterStatus,
                    searchQuery: _searchQuery,
                    onGoRepos: widget.onGoRepos,
                  )
                : const SkillDiscoverySkillsShBody(),
          ),
        ],
      ),
    );
  }
}

class _SkillDiscoverySourceRow extends StatelessWidget {
  const _SkillDiscoverySourceRow({
    required this.source,
    required this.onSourceChanged,
  });

  final SkillSearchSource source;
  final ValueChanged<SkillSearchSource> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        SkillSourceToggle(
          label: l10n.skillsSourceRepos,
          selected: source == SkillSearchSource.repos,
          onTap: () => onSourceChanged(SkillSearchSource.repos),
        ),
        const SizedBox(width: 8),
        SkillSourceToggle(
          label: l10n.skillsSourceSkillsSh,
          selected: source == SkillSearchSource.skillsSh,
          onTap: () => onSourceChanged(SkillSearchSource.skillsSh),
        ),
        const Spacer(),
        if (source == SkillSearchSource.repos) const _SkillDiscoveryRefreshButton(),
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
        final syncing = sync.discoveryLoading || sync.repoSyncingKeys.isNotEmpty;
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
              : Icon(Icons.refresh, size: context.appIconSizes.md),
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
