import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import 'skill_discover_card.dart';
import 'skill_discovery_helpers.dart';
import '../../widgets/empty_state_block.dart';
import 'skill_management_cards.dart';

class SkillDiscoveryReposFilters extends StatelessWidget {
  const SkillDiscoveryReposFilters({
    required this.state,
    required this.filterRepo,
    required this.filterStatus,
    required this.onSearchChanged,
    required this.onFilterRepoChanged,
    required this.onFilterStatusChanged,
    super.key,
  });

  final SkillState state;
  final String filterRepo;
  final String filterStatus;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterRepoChanged;
  final ValueChanged<String> onFilterStatusChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final repoChoices = skillDiscoveryRepoFilterChoices(state, l10n);
    final repoItems = repoChoices.keys.toList()
      ..sort((a, b) {
        if (a == 'all') return -1;
        if (b == 'all') return 1;
        return repoChoices[a]!.compareTo(repoChoices[b]!);
      });
    final effectiveRepo = resolveSkillDiscoveryRepoFilter(filterRepo, repoChoices);
    if (effectiveRepo != filterRepo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onFilterRepoChanged(effectiveRepo);
      });
    }
    String repoLabel(String v) => repoChoices[v] ?? v;

    String statusLabel(String v) {
      switch (v) {
        case 'installed':
          return l10n.skillsFilterInstalled;
        case 'uninstalled':
          return l10n.skillsFilterUninstalled;
        case 'all':
        default:
          return l10n.skillsFilterAll;
      }
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: InputDecoration(
              hintText: l10n.skillsSearchPlaceholder,
              prefixIcon: Icon(Icons.search, size: context.appIconSizes.md),
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          width: 300,
          child: AppDropdownField<String>(
            key: ValueKey(repoItems.join('|')),
            items: repoItems,
            initialItem: effectiveRepo,
            overlayHeight: 320,
            headerMaxLines: 2,
            listItemMaxLines: 2,
            itemLabel: repoLabel,
            onChanged: (v) => onFilterRepoChanged(v ?? 'all'),
          ),
        ),
        SizedBox(
          width: 160,
          child: AppDropdownField<String>(
            items: const ['all', 'installed', 'uninstalled'],
            initialItem: filterStatus,
            overlayHeight: 200,
            itemLabel: statusLabel,
            onChanged: (v) => onFilterStatusChanged(v ?? 'all'),
          ),
        ),
      ],
    );
  }
}

class SkillDiscoveryReposGrid extends StatelessWidget {
  const SkillDiscoveryReposGrid({
    required this.state,
    required this.installedKeys,
    required this.filterRepo,
    required this.filterStatus,
    required this.searchQuery,
    required this.onGoRepos,
    super.key,
  });

  final SkillState state;
  final Set<String> installedKeys;
  final String filterRepo;
  final String filterStatus;
  final String searchQuery;
  final VoidCallback onGoRepos;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.discoveryLoading && state.discoverable.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final filtered = filterDiscoverableSkills(
      state: state,
      installedKeys: installedKeys,
      filterRepo: filterRepo,
      filterStatus: filterStatus,
      searchQuery: searchQuery,
    );
    if (!state.discoveryLoading && filtered.isEmpty) {
      return SkillManagementCard(
        child: EmptyStateBlock(
          icon: Icons.travel_explore_outlined,
          title: l10n.skillsDiscoveryEmpty,
          hint: l10n.skillsDiscoveryEmptyHint,
          actionLabel: state.repos.isEmpty ? l10n.skillsRepoAdd : null,
          onAction: state.repos.isEmpty ? onGoRepos : null,
        ),
      );
    }

    return Expanded(
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 380,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 168,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final skill = filtered[index];
          final installKey = discoverableSkillInstallKey(skill);
          return SkillDiscoverCard(
            name: skill.name,
            description: skill.description,
            source: '${skill.repoOwner}/${skill.repoName}',
            githubUrl: skill.githubBrowseUrl,
            installed: installedKeys.contains(installKey),
            busy: state.busyIds.contains(skill.key),
            onInstall: () =>
                context.read<SkillCubit>().installFromDiscovery(skill),
          );
        },
      ),
    );
  }
}
