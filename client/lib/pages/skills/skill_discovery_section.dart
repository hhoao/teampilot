import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import 'skill_discovery_helpers.dart';
import 'skill_discovery_repos_panel.dart';
import 'skill_discovery_skills_sh_panel.dart';
import 'skill_management_cards.dart';
import 'skill_source_toggle.dart';

class SkillDiscoverySection extends StatefulWidget {
  const SkillDiscoverySection({
    super.key,
    required this.state,
    required this.onGoRepos,
  });

  final SkillState state;
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
  void dispose() {
    _skillsShCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final cubit = context.read<SkillCubit>();
    final installedKeys = state.installed
        .map(
          (s) =>
              '${s.directory.toLowerCase()}:${(s.repoOwner ?? '').toLowerCase()}:${(s.repoName ?? '').toLowerCase()}',
        )
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkillManagementCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SkillSourceToggle(
                    label: l10n.skillsSourceRepos,
                    selected: _source == SkillSearchSource.repos,
                    onTap: () =>
                        setState(() => _source = SkillSearchSource.repos),
                  ),
                  const SizedBox(width: 8),
                  SkillSourceToggle(
                    label: l10n.skillsSourceSkillsSh,
                    selected: _source == SkillSearchSource.skillsSh,
                    onTap: () =>
                        setState(() => _source = SkillSearchSource.skillsSh),
                  ),
                  const Spacer(),
                  if (_source == SkillSearchSource.repos)
                    IconButton(
                      tooltip: l10n.skillsCheckUpdates,
                      onPressed: state.discoveryLoading
                          ? null
                          : () => cubit.refreshDiscoverable(),
                      icon:
                          state.discoveryLoading ||
                              state.repoSyncingKeys.isNotEmpty
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: AppIconSizes.md),
                    ),
                ],
              ),
              if (_source == SkillSearchSource.repos &&
                  state.repoSyncingKeys.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.skillsDiscoverySyncing,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              if (_source == SkillSearchSource.repos)
                SkillDiscoveryReposFilters(
                  state: state,
                  filterRepo: _filterRepo,
                  filterStatus: _filterStatus,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onFilterRepoChanged: (v) => setState(() => _filterRepo = v),
                  onFilterStatusChanged: (v) =>
                      setState(() => _filterStatus = v),
                )
              else
                SkillDiscoverySkillsShSearchBar(
                  controller: _skillsShCtl,
                  onSearch: cubit.searchSkillsSh,
                ),
            ],
          ),
        ),
        if (_source == SkillSearchSource.repos)
          SkillDiscoveryReposGrid(
            state: state,
            installedKeys: installedKeys,
            filterRepo: _filterRepo,
            filterStatus: _filterStatus,
            searchQuery: _searchQuery,
            onGoRepos: widget.onGoRepos,
          )
        else
          SkillDiscoverySkillsShResults(
            state: state,
            installedKeys: installedKeys,
          ),
      ],
    );
  }
}
