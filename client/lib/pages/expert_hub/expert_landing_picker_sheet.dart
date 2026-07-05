import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../services/expert_hub/expert_hub_recent_store.dart';
import '../../theme/app_text_styles.dart';
import '../home_workspace/home_workspace_global_section.dart';
import 'expert_hub_visuals.dart';

/// Bottom sheet for choosing an expert on the workspace landing compose bar.
Future<String?> showExpertLandingPickerSheet(
  BuildContext context, {
  String? selectedKey,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ExpertLandingPickerSheet(selectedKey: selectedKey),
  );
}

/// Apply-mode picker for team member config — invokes [onApply] instead of
/// returning a landing expert key.
Future<void> showExpertApplyPickerSheet(
  BuildContext context, {
  required ValueChanged<DiscoverableMember> onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ExpertLandingPickerSheet(onApply: onApply),
  );
}

class ExpertLandingPickerSheet extends StatefulWidget {
  const ExpertLandingPickerSheet({
    this.selectedKey,
    this.onApply,
    super.key,
  });

  final String? selectedKey;

  /// When set, selection applies the member and closes without returning a key.
  final ValueChanged<DiscoverableMember>? onApply;

  @override
  State<ExpertLandingPickerSheet> createState() =>
      _ExpertLandingPickerSheetState();
}

class _ExpertLandingPickerSheetState extends State<ExpertLandingPickerSheet> {
  final _searchController = TextEditingController();
  final _recentStore = ExpertHubRecentStore();
  var _search = '';
  List<String> _recentKeys = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
    final cubit = context.read<ExpertHubCubit>();
    if (cubit.state.allMembers.isEmpty &&
        cubit.state.status != ExpertHubLoadStatus.loading) {
      unawaited(cubit.load());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final keys = await _recentStore.loadOrderedKeys();
    if (!mounted) return;
    setState(() => _recentKeys = keys);
  }

  void _onSearchChanged(String value) => setState(() => _search = value);

  DiscoverableMember? _memberForKey(
    String key,
    List<DiscoverableMember> members,
  ) {
    for (final member in members) {
      if (member.key == key) return member;
    }
    return null;
  }

  List<DiscoverableMember> _filteredMembers(List<DiscoverableMember> members) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return members;
    return members
        .where(
          (m) =>
              m.name.toLowerCase().contains(q) ||
              m.description.toLowerCase().contains(q) ||
              m.tags.any((t) => t.toLowerCase().contains(q)),
        )
        .toList();
  }

  List<DiscoverableMember> _orderedSection({
    required Iterable<String> keys,
    required List<DiscoverableMember> members,
  }) {
    final out = <DiscoverableMember>[];
    for (final key in keys) {
      final member = _memberForKey(key, members);
      if (member != null) out.add(member);
    }
    return out;
  }

  void _select(DiscoverableMember member) {
    final onApply = widget.onApply;
    if (onApply != null) {
      onApply(member);
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(member.key);
  }

  void _openExpertHub() {
    Navigator.of(context).pop();
    context.go(HomeGlobalView.expertHub.homeLocation);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final state = context.watch<ExpertHubCubit>().state;
    final allMembers = state.allMembers;
    final favorites = _orderedSection(
      keys: state.favorites,
      members: allMembers,
    );
    final recent = _orderedSection(keys: _recentKeys, members: allMembers);
    final filtered = _filteredMembers(allMembers);
    final selectedKey = widget.selectedKey?.trim() ?? '';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  l10n.expertHubTitle,
                  style: styles.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.expertHubSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              if (state.status == ExpertHubLoadStatus.loading &&
                  allMembers.isEmpty)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      if (_search.isEmpty && favorites.isNotEmpty) ...[
                        _SectionHeader(title: l10n.expertHubFavorites),
                        for (final member in favorites)
                          _MemberTile(
                            member: member,
                            selected: member.key == selectedKey,
                            onTap: () => _select(member),
                          ),
                      ],
                      if (_search.isEmpty && recent.isNotEmpty) ...[
                        _SectionHeader(title: l10n.expertHubRecent),
                        for (final member in recent)
                          _MemberTile(
                            member: member,
                            selected: member.key == selectedKey,
                            onTap: () => _select(member),
                          ),
                      ],
                      if (_search.isNotEmpty || filtered.isNotEmpty) ...[
                        if (_search.isEmpty &&
                            (favorites.isNotEmpty || recent.isNotEmpty))
                          _SectionHeader(title: l10n.expertHubCategoryAll),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              l10n.expertHubEmptyTitle,
                              style: styles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          for (final member in filtered)
                            _MemberTile(
                              member: member,
                              selected: member.key == selectedKey,
                              onTap: () => _select(member),
                            ),
                      ],
                    ],
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: TextButton(
                  onPressed: _openExpertHub,
                  child: Text(l10n.expertHubBrowseAll),
                ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        title,
        style: AppTextStyles.of(context).bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final DiscoverableMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: TeamMonogram(
        seed: member.key,
        label: member.name,
        size: 36,
      ),
      title: Text(
        member.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: member.description.trim().isEmpty
          ? null
          : Text(
              member.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: selected
          ? Icon(Icons.check, size: 18, color: cs.primary)
          : null,
      onTap: onTap,
    );
  }
}
