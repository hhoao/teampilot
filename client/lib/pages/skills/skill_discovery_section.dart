import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/github_details_button.dart';
import 'skill_management_cards.dart';

enum SkillSearchSource { repos, skillsSh }

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

  /// Filter value → short label (`owner/name`) for the repo dropdown.
  Map<String, String> _repoFilterChoices(
    SkillState state,
    AppLocalizations l10n,
  ) {
    final choices = <String, String>{'all': l10n.skillsFilterRepoAll};
    for (final r in state.repos.where((r) => r.enabled)) {
      choices[r.githubUrl] = r.fullName;
    }
    for (final d in state.discoverable) {
      final url = 'https://github.com/${d.repoOwner}/${d.repoName}';
      choices.putIfAbsent(url, () => '${d.repoOwner}/${d.repoName}');
    }
    return choices;
  }

  String _resolveRepoFilter(String raw, Map<String, String> choices) {
    if (choices.containsKey(raw)) return raw;
    final byLabel = choices.entries.where((e) => e.value == raw).toList();
    if (byLabel.length == 1) return byLabel.first.key;
    return 'all';
  }

  bool _matchesRepoFilter(DiscoverableSkill d) {
    if (_filterRepo == 'all') return true;
    final url = 'https://github.com/${d.repoOwner}/${d.repoName}';
    return url == _filterRepo || '${d.repoOwner}/${d.repoName}' == _filterRepo;
  }

  List<DiscoverableSkill> _filtered(Set<String> installedKeys) {
    return widget.state.discoverable.where((d) {
      if (!_matchesRepoFilter(d)) return false;
      final installKey =
          '${d.directory.split('/').last.toLowerCase()}:${d.repoOwner.toLowerCase()}:${d.repoName.toLowerCase()}';
      final installed = installedKeys.contains(installKey);
      if (_filterStatus == 'installed' && !installed) return false;
      if (_filterStatus == 'uninstalled' && installed) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          '${d.repoOwner}/${d.repoName}'.toLowerCase().contains(q);
    }).toList();
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
                          : const Icon(Icons.refresh, size: 18),
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
                _buildReposFilters(context, state)
              else
                _buildSkillsShInput(context, cubit, l10n),
            ],
          ),
        ),
        if (_source == SkillSearchSource.repos)
          _buildReposGrid(context, state, installedKeys)
        else
          _buildSkillsShGrid(context, state, cubit, installedKeys),
      ],
    );
  }

  Widget _buildReposFilters(BuildContext context, SkillState state) {
    final l10n = context.l10n;
    final repoChoices = _repoFilterChoices(state, l10n);
    final repoItems = repoChoices.keys.toList()
      ..sort((a, b) {
        if (a == 'all') return -1;
        if (b == 'all') return 1;
        return repoChoices[a]!.compareTo(repoChoices[b]!);
      });
    final effectiveRepo = _resolveRepoFilter(_filterRepo, repoChoices);
    if (effectiveRepo != _filterRepo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _filterRepo = effectiveRepo);
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
              prefixIcon: const Icon(Icons.search, size: 18),
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
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
            onChanged: (v) => setState(() => _filterRepo = v ?? 'all'),
          ),
        ),
        SizedBox(
          width: 160,
          child: AppDropdownField<String>(
            items: const ['all', 'installed', 'uninstalled'],
            initialItem: _filterStatus,
            overlayHeight: 200,
            itemLabel: statusLabel,
            onChanged: (v) => setState(() => _filterStatus = v ?? 'all'),
          ),
        ),
      ],
    );
  }

  Widget _buildSkillsShInput(
    BuildContext context,
    SkillCubit cubit,
    AppLocalizations l10n,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _skillsShCtl,
            decoration: InputDecoration(
              hintText: l10n.skillsSkillsShPlaceholder,
              prefixIcon: const Icon(Icons.search, size: 18),
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onSubmitted: (v) {
              if (v.trim().length >= 2) cubit.searchSkillsSh(v.trim());
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _skillsShCtl.text.trim().length < 2
              ? null
              : () => cubit.searchSkillsSh(_skillsShCtl.text.trim()),
          child: Text(l10n.skillsSkillsShSearch),
        ),
      ],
    );
  }

  Widget _buildReposGrid(
    BuildContext context,
    SkillState state,
    Set<String> installedKeys,
  ) {
    final l10n = context.l10n;
    if (state.discoveryLoading && state.discoverable.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final filtered = _filtered(installedKeys);
    if (!state.discoveryLoading && filtered.isEmpty) {
      return SkillManagementCard(
        child: SkillEmptyBlock(
          icon: Icons.travel_explore_outlined,
          title: l10n.skillsDiscoveryEmpty,
          hint: l10n.skillsDiscoveryEmptyHint,
          actionLabel: state.repos.isEmpty ? l10n.skillsRepoAdd : null,
          onAction: state.repos.isEmpty ? widget.onGoRepos : null,
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
          final d = filtered[index];
          final installKey =
              '${d.directory.split('/').last.toLowerCase()}:${d.repoOwner.toLowerCase()}:${d.repoName.toLowerCase()}';
          return SkillDiscoverCard(
            name: d.name,
            description: d.description,
            source: '${d.repoOwner}/${d.repoName}',
            githubUrl: d.githubBrowseUrl,
            installed: installedKeys.contains(installKey),
            busy: state.busyIds.contains(d.key),
            onInstall: () => context.read<SkillCubit>().installFromDiscovery(d),
          );
        },
      ),
    );
  }

  Widget _buildSkillsShGrid(
    BuildContext context,
    SkillState state,
    SkillCubit cubit,
    Set<String> installedKeys,
  ) {
    final l10n = context.l10n;
    final sh = state.skillsSh;
    if (sh.loading && sh.entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (sh.query.isEmpty) {
      return SkillManagementCard(
        child: SkillEmptyBlock(
          icon: Icons.search,
          title: l10n.skillsSkillsShPlaceholder,
          hint: '',
        ),
      );
    }
    if (sh.entries.isEmpty) {
      return SkillManagementCard(
        child: SkillEmptyBlock(
          icon: Icons.search_off,
          title: l10n.skillsDiscoveryEmpty,
          hint: l10n.skillsDiscoveryEmptyHint,
        ),
      );
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1100
                ? 3
                : (constraints.maxWidth >= 700 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 168,
              ),
              itemCount: sh.entries.length,
              itemBuilder: (context, i) {
                final e = sh.entries[i];
                final installKey =
                    '${e.directory.toLowerCase()}:${e.repoOwner.toLowerCase()}:${e.repoName.toLowerCase()}';
                return SkillDiscoverCard(
                  name: e.name,
                  description: l10n.skillsInstalls(e.installs),
                  source: '${e.repoOwner}/${e.repoName}',
                  githubUrl: e.githubBrowseUrl,
                  installed: installedKeys.contains(installKey),
                  busy: state.busyIds.contains(e.key),
                  onInstall: () => cubit.installSkillsShEntry(e),
                );
              },
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              if (sh.entries.length < sh.totalCount)
                OutlinedButton.icon(
                  onPressed: sh.loading ? null : cubit.loadMoreSkillsSh,
                  icon: sh.loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more, size: 16),
                  label: Text(l10n.skillsSkillsShLoadMore),
                ),
              const SizedBox(height: 6),
              Text(
                l10n.skillsSkillsShPoweredBy,
                style: AppTextStyles.of(
                  context,
                ).caption.copyWith(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SkillSourceToggle extends StatelessWidget {
  const SkillSourceToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? cs.primaryContainer : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.of(context).body.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class SkillDiscoverCard extends StatelessWidget {
  const SkillDiscoverCard({
    super.key,
    required this.name,
    required this.description,
    required this.source,
    this.githubUrl,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final String name;
  final String description;
  final String source;
  final String? githubUrl;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: workspaceCardDecoration(cs, radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.of(context).bodyStrong.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textBase,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source,
            style: AppTextStyles.of(
              context,
            ).caption.copyWith(color: textBase.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.of(
                context,
              ).bodySmall.copyWith(color: textBase.withValues(alpha: 0.7)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GithubDetailsButton(
                  url: githubUrl,
                  label: l10n.skillsCardDetails,
                ),
                if (installed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.skillsCardInstalled,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: const Color(0xFF15803D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: busy ? null : onInstall,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.skillsCardInstall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
