import 'package:flutter/material.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/empty_state_block.dart';
import 'expert_hub_cards.dart';

/// Single-page hub body: a toolbar (search + sort), an inline filter-chip bar
/// (favorites, source filters, category single-select), then the member grid.
class ExpertHubBody extends StatefulWidget {
  const ExpertHubBody({
    super.key,
    required this.cubit,
    required this.onOpen,
    this.onCreate,
    this.inset = 28,
  });

  final ExpertHubCubit cubit;
  final void Function(DiscoverableMember) onOpen;

  /// Opens the shared expert editor (create). When null, the create button is
  /// still shown but does nothing until the page wires it.
  final VoidCallback? onCreate;

  /// Horizontal page inset (tighter on Android).
  final double inset;

  @override
  State<ExpertHubBody> createState() => _ExpertHubBodyState();
}

class _ExpertHubBodyState extends State<ExpertHubBody> {
  @override
  void dispose() {
    Debounces.cancel('expert_hub_search');
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Debounces.debounce(
      'expert_hub_search',
      const Duration(milliseconds: 400),
      () => widget.cubit.setSearch(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.cubit.state;
    final members = widget.cubit.visibleMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(widget.inset, 18, widget.inset, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l10n.expertHubSearchHint,
                    prefixIcon: Icon(
                      Icons.search,
                      size: context.appIconSizes.md,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: AppDropdownField<MemberSort>(
                  items: const [MemberSort.name, MemberSort.updated],
                  initialItem: state.sort,
                  itemLabel: (s) => switch (s) {
                    MemberSort.name => l10n.expertHubSortName,
                    MemberSort.updated => l10n.expertHubSortUpdated,
                  },
                  onChanged: (s) => s == null ? null : widget.cubit.setSort(s),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                key: const Key('expert-hub-create'),
                onPressed: () => widget.onCreate?.call(),
                icon: const Icon(Icons.add),
                label: Text(l10n.expertHubCreate),
              ),
            ],
          ),
        ),
        _FilterBar(cubit: widget.cubit, inset: widget.inset),
        Expanded(child: _grid(context, state, members)),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    ExpertHubState state,
    List<DiscoverableMember> members,
  ) {
    final l10n = context.l10n;
    if (state.status == ExpertHubLoadStatus.loading && members.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (members.isEmpty) {
      final isError = state.status == ExpertHubLoadStatus.error;
      if (state.favoritesOnly && !isError) {
        return EmptyStateBlock(
          centered: true,
          icon: Icons.star_outline_rounded,
          title: l10n.expertHubFavoritesEmptyTitle,
          hint: l10n.expertHubFavoritesEmptyHint,
        );
      }
      return Padding(
        padding: EdgeInsets.all(widget.inset),
        child: EmptyStateBlock(
          centered: true,
          icon: isError
              ? Icons.cloud_off_outlined
              : Icons.travel_explore_outlined,
          title: isError ? l10n.expertHubLoadError : l10n.expertHubEmptyTitle,
          hint: isError ? null : l10n.expertHubEmptyHint,
          actionLabel: l10n.expertHubRefresh,
          onAction: () => widget.cubit.load(forceRefresh: true),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(widget.inset, 4, widget.inset, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 186,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: members.length,
      itemBuilder: (context, i) {
        final m = members[i];
        return ExpertHubCard(
          member: m,
          favorited: state.favorites.contains(m.key),
          busy: state.addingKeys.contains(m.key),
          onTap: () => widget.onOpen(m),
          onToggleFavorite: () => widget.cubit.toggleFavorite(m.key),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.cubit, required this.inset});

  final ExpertHubCubit cubit;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final state = cubit.state;
    final counts = state.categoryCounts;
    final selected = state.selectedCategory;

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
        children: [
          _FilterPill(
            label: l10n.expertHubFavorites,
            icon: state.favoritesOnly
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            selected: state.favoritesOnly,
            onTap: () => cubit.setFavoritesOnly(!state.favoritesOnly),
          ),
          _FilterPill(
            label: l10n.expertHubMyTemplates,
            icon: Icons.note_alt_outlined,
            selected: state.localOnly,
            onTap: () => cubit.setLocalOnly(!state.localOnly),
          ),
          _FilterPill(
            label: l10n.expertHubFromTeams,
            icon: Icons.groups_outlined,
            selected: state.teamExtractOnly,
            onTap: () => cubit.setTeamExtractOnly(!state.teamExtractOnly),
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
            label: l10n.expertHubCategoryAll,
            count: state.allMembers.length,
            selected: selected == null,
            onTap: () => cubit.setCategory(null),
          ),
          for (final c in state.categories)
            _FilterPill(
              label: c,
              count: counts[c] ?? 0,
              selected: selected == c,
              onTap: () => cubit.setCategory(c),
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
    final styles = AppTextStyles.of(context);
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
                Text(label, style: styles.mdColored(fg)),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: styles.xsColored(selected
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
