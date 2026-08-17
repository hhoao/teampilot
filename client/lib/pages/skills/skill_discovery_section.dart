import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../services/skill/registry/skill_registry_source.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/workspace_library_card.dart';
import 'marketplace_skill_card.dart';
import 'skill_discovery_helpers.dart';

class SkillDiscoverySection extends StatefulWidget {
  const SkillDiscoverySection({super.key, required this.onGoRegistries});

  final VoidCallback onGoRegistries;

  @override
  State<SkillDiscoverySection> createState() => SkillDiscoverySectionState();
}

class SkillDiscoverySectionState extends State<SkillDiscoverySection> {
  final _searchCtl = TextEditingController();
  String _query = '';
  String _sourceFilter = 'all';
  String _statusFilter = 'all';
  String? _sortBy;
  String? _language;
  String? _category;
  String? _occupation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cubit = context.read<SkillCubit>();
      await cubit.ensureDiscoveryLoaded();
      if (!mounted) return;
      await cubit.unifiedBrowse();
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    Debounces.cancel('skill_discovery_search');
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Debounces.debounce('skill_discovery_search', const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final q = value.trim();
      setState(() => _query = q);
      final cubit = context.read<SkillCubit>();
      if (q.length >= 2) {
        cubit.unifiedSearch(q, sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
      } else {
        cubit.unifiedSearch('', sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
      }
    });
  }

  String? _sourceIdOrNull() => _sourceFilter == 'all' ? null : _sourceFilter;

  void _onFilterChanged() {
    final cubit = context.read<SkillCubit>();
    if (_query.trim().length >= 2) {
      cubit.unifiedSearch(_query.trim(), sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
    } else {
      cubit.unifiedSearch('', sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceLibraryCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterBar(
                searchCtl: _searchCtl,
                onSearchChanged: _onSearchChanged,
                sourceFilter: _sourceFilter,
                statusFilter: _statusFilter,
                onSourceFilter: (v) {
                  setState(() => _sourceFilter = v ?? 'all');
                  _onFilterChanged();
                },
                onStatusFilter: (v) {
                  setState(() => _statusFilter = v ?? 'all');
                },
                onRefresh: () => context.read<SkillCubit>().unifiedSearch(
                  _query.trim().length >= 2 ? _query.trim() : '',
                  sourceId: _sourceIdOrNull(),
                  sortBy: _sortBy, language: _language,
                  category: _category, occupation: _occupation,
                ),
              ),
              const _SyncBanner(),
            ],
          ),
        ),
        Expanded(
          child: _ResultsBody(
            query: _query,
            sourceFilter: _sourceFilter,
            statusFilter: _statusFilter,
            onGoRegistries: widget.onGoRegistries,
            onRetry: _onFilterChanged,
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtl,
    required this.onSearchChanged,
    required this.sourceFilter,
    required this.statusFilter,
    required this.onSourceFilter,
    required this.onStatusFilter,
    required this.onRefresh,
  });

  final TextEditingController searchCtl;
  final ValueChanged<String> onSearchChanged;
  final String sourceFilter;
  final String statusFilter;
  final ValueChanged<String?> onSourceFilter;
  final ValueChanged<String?> onStatusFilter;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<SkillCubit, SkillState, List<SkillRegistrySource>>(
      selector: (state) => state.sources,
      builder: (context, sources) {
        final enabled = sources.where((s) => s.enabled).toList();
        final sourceItems = <String, String>{
          'all': l10n.skillsFilterRepoAll,
          for (final s in enabled) s.id: s.label,
        };
        String statusLabel(String v) => switch (v) {
          'installed' => l10n.skillsFilterInstalled,
          'uninstalled' => l10n.skillsFilterUninstalled,
          _ => l10n.skillsFilterAll,
        };
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: searchCtl,
                decoration: InputDecoration(
                  hintText: l10n.skillsSearchPlaceholder,
                  prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                onChanged: onSearchChanged,
              ),
            ),
            SizedBox(
              width: 220,
              child: TpSelect<String>(
                key: ValueKey(sourceItems.keys.join('|')),
                items: sourceItems.keys.toList(),
                initialItem: sourceItems.containsKey(sourceFilter) ? sourceFilter : 'all',
                itemLabel: (v) => sourceItems[v] ?? v,
                onChanged: onSourceFilter,
              ),
            ),
            SizedBox(
              width: 160,
              child: TpSelect<String>(
                items: const ['all', 'installed', 'uninstalled'],
                initialItem: statusFilter,
                itemLabel: statusLabel,
                onChanged: onStatusFilter,
              ),
            ),
            IconButton(
              tooltip: l10n.skillsCheckUpdates,
              onPressed: onRefresh,
              icon: Icon(Icons.refresh, size: context.tpIconSizes.md),
            ),
          ],
        );
      },
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SkillCubit, SkillState, Set<String>>(
      selector: (state) => state.repoSyncingKeys,
      builder: (context, syncing) {
        if (syncing.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.skillsDiscoverySyncing, style: TpTextStyles.of(context).sm),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({
    required this.query,
    required this.sourceFilter,
    required this.statusFilter,
    required this.onGoRegistries,
    required this.onRetry,
  });

  final String query;
  final String sourceFilter;
  final String statusFilter;
  final VoidCallback onGoRegistries;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<SkillCubit, SkillState, Set<String>>(
      selector: (state) => skillInstalledKeys(state.installed),
      builder: (context, installedKeys) {
        return BlocSelector<SkillCubit, SkillState, SkillUnifiedGridSlice>(
          selector: (state) => (
            entries: state.discoveryEntries,
            discoveryLoading: state.discoveryLoading,
            anyHasNext: state.anyDiscoveryHasNext,
            busyIds: state.busyIds,
            discoveryError: state.discoveryError,
          ),
          builder: (context, grid) {
            final error = grid.discoveryError;
            if (error != null) {
              return _ErrorBody(
                error: error,
                onGoRegistries: onGoRegistries,
                onRetry: onRetry,
              );
            }
            if (grid.discoveryLoading && grid.entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final filtered = grid.entries.where((e) {
              if (sourceFilter != 'all' && e.sourceId != sourceFilter) return false;
              return unifiedEntryMatchesStatus(e, installedKeys, statusFilter);
            }).toList();

            if (grid.discoveryLoading && filtered.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (filtered.isEmpty) {
              return SingleChildScrollView(
                child: WorkspaceLibraryCard(
                  child: TpEmptyState(
                    icon: Icons.travel_explore_outlined,
                    title: l10n.skillsDiscoveryEmpty,
                    hint: l10n.skillsDiscoveryEmptyHint,
                    actionLabel: l10n.skillsRegistryGoSetKey,
                    onAction: onGoRegistries,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 1100 ? 3 : (constraints.maxWidth >= 700 ? 2 : 1);
                      return GridView.builder(
                        padding: const EdgeInsets.only(top: 2),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 168,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final entry = filtered[i];
                          return MarketplaceSkillCard(
                            key: ValueKey('${entry.sourceId}:${entry.skill.key}'),
                            skill: entry.skill,
                            installed: installedKeys.contains(
                              '${(entry.skill.directory ?? entry.skill.repoName).split('/').last.toLowerCase()}:${entry.skill.repoOwner.toLowerCase()}:${entry.skill.repoName.toLowerCase()}',
                            ),
                            busy: grid.busyIds.contains(entry.skill.key),
                            onInstall: () => context.read<SkillCubit>().installUnifiedEntry(entry),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (grid.anyHasNext)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: grid.discoveryLoading
                          ? null
                          : () => context.read<SkillCubit>().unifiedLoadMore(),
                      icon: grid.discoveryLoading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.expand_more, size: context.tpIconSizes.md),
                      label: Text(l10n.skillsMarketplaceLoadMore),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.onGoRegistries,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onGoRegistries;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isQuota = error == marketplaceQuotaErrorKey;
    return SingleChildScrollView(
      child: WorkspaceLibraryCard(
        child: Column(
          children: [
            TpEmptyState(
              icon: isQuota ? Icons.key_off_outlined : Icons.error_outline,
              title: l10n.skillsDiscoveryErrorTitle,
              hint: isQuota ? l10n.skillsMpQuotaHint : error,
              actionLabel: isQuota ? l10n.skillsRegistryGoSetKey : null,
              onAction: isQuota ? onGoRegistries : null,
              centered: true,
            ),
            if (isQuota) const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.skillsRegistryRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
