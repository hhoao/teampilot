import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../utils/debounce/debounce.dart';
import 'marketplace_skill_card.dart';
import 'skill_discovery_helpers.dart';
import 'skill_management_cards.dart';

class SkillMarketplacePanel extends StatefulWidget {
  const SkillMarketplacePanel({super.key, required this.source});

  final SkillMarketplaceSource source;

  @override
  State<SkillMarketplacePanel> createState() => _SkillMarketplacePanelState();
}

class _SkillMarketplacePanelState extends State<SkillMarketplacePanel> {
  final _searchCtl = TextEditingController();
  String? _sortBy;
  String? _language;
  String? _category;
  String? _occupation;

  @override
  void dispose() {
    Debounces.cancel('skill_marketplace_search');
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSubmitted(String value) {
    final q = value.trim();
    if (q.length < 2) return;
    context.read<SkillCubit>().searchMarketplace(
      widget.source.id,
      query: q,
      category: _category,
      occupation: _occupation,
      language: _language,
      sortBy: _sortBy,
    );
  }

  void _search() {
    final q = _searchCtl.text.trim();
    if (q.length >= 2) _onSubmitted(q);
  }

  void _onFilterChanged() {
    final q = _searchCtl.text.trim();
    if (q.length >= 2) {
      context.read<SkillCubit>().searchMarketplace(
        widget.source.id,
        query: q,
        category: _category,
        occupation: _occupation,
        language: _language,
        sortBy: _sortBy,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SkillCubit, SkillState, MarketplaceSearchState>(
      selector: (state) =>
          state.marketplace[widget.source.id] ?? const MarketplaceSearchState(),
      builder: (context, slot) {
        final l10n = context.l10n;
        final caps = widget.source.capabilities;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      hintText: l10n.skillsMarketplaceSearchHint,
                      prefixIcon: Icon(
                        Icons.search,
                        size: context.tpIconSizes.md,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    onSubmitted: _onSubmitted,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _search,
                  child: Text(l10n.skillsSkillsShSearch),
                ),
              ],
            ),
            if (caps.hasAnyFilter) ...[
              const SizedBox(height: 10),
              _FilterRow(
                caps: caps,
                sortBy: _sortBy,
                language: _language,
                category: _category,
                occupation: _occupation,
                onSortBy: (v) {
                  setState(() => _sortBy = v);
                  _onFilterChanged();
                },
                onLanguage: (v) {
                  setState(() => _language = v);
                  _onFilterChanged();
                },
                onCategory: (v) {
                  setState(() => _category = v);
                  _onFilterChanged();
                },
                onOccupation: (v) {
                  setState(() => _occupation = v);
                  _onFilterChanged();
                },
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _body(context, slot, l10n)),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    MarketplaceSearchState slot,
    AppLocalizations l10n,
  ) {
    if (slot.loading && slot.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (slot.error != null) {
      return _ErrorState(
        error: slot.error!,
        onRetry: () {
          context.read<SkillCubit>().clearMarketplaceError(widget.source.id);
          _onFilterChanged();
        },
        onSetApiKey: () => _showApiKeyDialog(context),
        sourceId: widget.source.id,
      );
    }
    if (slot.query.isEmpty) {
      return SingleChildScrollView(
        child: SkillManagementCard(
          child: TpEmptyState(
            icon: Icons.search,
            title: l10n.skillsSkillsShPlaceholder,
            hint: '',
          ),
        ),
      );
    }
    if (slot.entries.isEmpty) {
      return SingleChildScrollView(
        child: SkillManagementCard(
          child: TpEmptyState(
            icon: Icons.search_off,
            title: l10n.skillsDiscoveryEmpty,
            hint: l10n.skillsDiscoveryEmptyHint,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: BlocSelector<SkillCubit, SkillState, Set<String>>(
            selector: (state) => skillInstalledKeys(state.installed),
            builder: (context, installedKeys) {
              return BlocSelector<SkillCubit, SkillState, Set<String>>(
                selector: (state) => state.busyIds,
                builder: (context, busyIds) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 1100
                          ? 3
                          : (constraints.maxWidth >= 700 ? 2 : 1);
                      return GridView.builder(
                        padding: const EdgeInsets.only(top: 2),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 168,
                        ),
                        itemCount: slot.entries.length,
                        itemBuilder: (context, i) {
                          final skill = slot.entries[i];
                          return MarketplaceSkillCard(
                            key: ValueKey('${widget.source.id}:${skill.key}'),
                            skill: skill,
                            installed: installedKeys.contains(
                              '${(skill.directory ?? skill.repoName).toLowerCase()}:${skill.repoOwner.toLowerCase()}:${skill.repoName.toLowerCase()}',
                            ),
                            busy: busyIds.contains(skill.key),
                            onInstall: () => context
                                .read<SkillCubit>()
                                .installMarketplaceEntry(skill),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        if (slot.hasNext)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: slot.loading
                  ? null
                  : () => context.read<SkillCubit>().loadMoreMarketplace(
                      widget.source.id,
                    ),
              icon: slot.loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.expand_more, size: context.tpIconSizes.md),
              label: Text(l10n.skillsMarketplaceLoadMore),
            ),
          ),
      ],
    );
  }

  Future<void> _showApiKeyDialog(BuildContext dialogContext) async {
    final l10n = context.l10n;
    final ctl = TextEditingController();
    final saved = await showDialog<String>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(l10n.skillsMpApiKeyDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.skillsMpApiKeyDialogHint,
              style: TpTextStyles.of(context).sm,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              decoration: InputDecoration(
                labelText: l10n.apiKey,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: Text(l10n.skillsMpApiKeySave),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (saved == null) return;
    if (!mounted) return;
    await context.read<SkillCubit>().setMarketplaceApiKey(
      widget.source.id,
      saved,
    );
    if (!mounted) return;
    _onFilterChanged();
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.caps,
    required this.sortBy,
    required this.language,
    required this.category,
    required this.occupation,
    required this.onSortBy,
    required this.onLanguage,
    required this.onCategory,
    required this.onOccupation,
  });

  final MarketplaceCapabilities caps;
  final String? sortBy;
  final String? language;
  final String? category;
  final String? occupation;
  final ValueChanged<String?> onSortBy;
  final ValueChanged<String?> onLanguage;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onOccupation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (caps.supportsSortBy)
          _FilterDropdown<String>(
            label: l10n.skillsFilterSortBy,
            value: sortBy,
            items: {
              'stars': l10n.skillsFilterSortByStars,
              'recent': l10n.skillsFilterSortByRecent,
            },
            onChanged: onSortBy,
          ),
        if (caps.supportsLanguage)
          _FilterDropdown<String>(
            label: l10n.skillsFilterLanguage,
            value: language,
            items: {
              for (final code in caps.languageChoices) code: code.toUpperCase(),
            },
            includeAny: l10n.skillsFilterAnyLanguage,
            onChanged: onLanguage,
          ),
        if (caps.supportsCategory)
          _FilterDropdown<String>(
            label: l10n.skillsFilterCategory,
            value: category,
            items: caps.categoryChoices,
            includeAny: l10n.skillsFilterAnyCategory,
            onChanged: onCategory,
          ),
        if (caps.supportsOccupation)
          _FilterDropdown<String>(
            label: l10n.skillsFilterOccupation,
            value: occupation,
            items: caps.occupationChoices,
            includeAny: l10n.skillsFilterAnyOccupation,
            onChanged: onOccupation,
          ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.includeAny,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final String? includeAny;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TpTextStyles.of(
            context,
          ).smColored(cs.onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            items: [
              if (includeAny != null)
                DropdownMenuItem<T>(value: null, child: Text(includeAny!)),
              for (final e in items.entries)
                DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
    required this.onSetApiKey,
    required this.sourceId,
  });

  final String error;
  final VoidCallback onRetry;
  final VoidCallback onSetApiKey;
  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isQuota = error == marketplaceQuotaErrorKey;
    return SingleChildScrollView(
      child: SkillManagementCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpEmptyState(
              icon: isQuota ? Icons.speed : Icons.error_outline,
              title: isQuota ? l10n.skillsMpQuotaHint : error,
              hint: '',
            ),
            if (isQuota) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: onSetApiKey,
                      child: Text(l10n.skillsMpApiKeyButton),
                    ),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: Text(l10n.skillsSkillsShSearch),
                    ),
                  ],
                ),
              ),
            ] else
              Align(
                alignment: Alignment.center,
                child: OutlinedButton(
                  onPressed: onRetry,
                  child: Text(l10n.skillsSkillsShSearch),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
