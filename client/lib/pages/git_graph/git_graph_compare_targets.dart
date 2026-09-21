import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_compare.dart';
import '../../models/git_graph.dart';
import '../git_compare/open_git_compare.dart';
import 'git_graph_filterable_action_menu_panel.dart';

int gitCompareTargetSearchableCount(GitGraphState state) =>
    state.branches.length +
    state.tags.length +
    state.rows.whereType<GitCommitRow>().length;

List<TpActionMenuSpec> gitCompareTargetSpecs({
  required AppLocalizations l10n,
  required GitGraphState state,
  required GitCompareRef source,
  String filterQuery = '',
}) {
  final needle = filterQuery.trim().toLowerCase();
  bool matches(String text) =>
      needle.isEmpty || text.toLowerCase().contains(needle);

  final locals = state.branches
      .where((b) => !b.isRemote && matches(b.name));
  final remotes = state.branches
      .where((b) => b.isRemote && matches(b.name));
  final tags = state.tags.where((t) => matches(t.name));
  final commits = state.rows.whereType<GitCommitRow>().where((row) {
    final label = '${GitCompareRef(row.hash).titleLabel()} ${row.subject}';
    return matches(label) || matches(row.hash);
  });
  final hasActiveFilter = needle.isNotEmpty;
  final refSectionsEmpty =
      locals.isEmpty && remotes.isEmpty && tags.isEmpty && commits.isEmpty;

  return [
    TpActionMenuSpec.item(
      value: const GitCompareWorkingTree(),
      icon: Icons.difference_outlined,
      label: l10n.gitGraphCompareWorkingTree(
        state.currentBranch.isEmpty ? 'HEAD' : state.currentBranch,
      ),
    ),
    const TpActionMenuSpec.divider(),
    if (refSectionsEmpty && hasActiveFilter)
      TpActionMenuSpec.item(
        icon: Icons.search_off_outlined,
        label: l10n.gitGraphRefsFilterEmpty,
        enabled: false,
      )
    else ...[
      if (locals.isNotEmpty) ...[
        _sectionHeader(Icons.call_split, l10n.gitGraphLocalBranches),
        TpActionMenuSpec.scroll(
          children: [
            for (final branch in locals)
              TpActionMenuSpec.item(
                value: GitCompareRef(branch.name),
                icon: Icons.call_split_outlined,
                label: branch.name,
                enabled: branch.name != source.nameOrHash,
              ),
          ],
        ),
      ],
      if (remotes.isNotEmpty) ...[
        _sectionHeader(Icons.cloud_outlined, l10n.gitGraphRemoteBranches),
        TpActionMenuSpec.scroll(
          children: [
            for (final branch in remotes)
              TpActionMenuSpec.item(
                value: GitCompareRef(branch.name),
                icon: Icons.cloud_outlined,
                label: branch.name,
                enabled: branch.name != source.nameOrHash,
              ),
          ],
        ),
      ],
      if (tags.isNotEmpty) ...[
        _sectionHeader(Icons.sell_outlined, l10n.gitGraphTags),
        TpActionMenuSpec.scroll(
          children: [
            for (final tag in tags)
              TpActionMenuSpec.item(
                value: GitCompareRef(tag.name),
                icon: Icons.sell_outlined,
                label: tag.name,
                enabled: tag.name != source.nameOrHash,
              ),
          ],
        ),
      ],
      if (commits.isNotEmpty) ...[
        _sectionHeader(Icons.commit, l10n.gitGraphCommits),
        TpActionMenuSpec.scroll(
          children: [
            for (final row in commits)
              TpActionMenuSpec.item(
                value: GitCompareRef(row.hash),
                icon: Icons.commit,
                label: '${GitCompareRef(row.hash).titleLabel()} ${row.subject}',
                enabled: row.hash != source.nameOrHash,
              ),
          ],
        ),
      ],
    ],
  ];
}

TpActionMenuSpec _sectionHeader(IconData icon, String label) =>
    TpActionMenuSpec.item(icon: icon, label: label, enabled: false);

Future<void> showGitCompareTargetMenu({
  required BuildContext context,
  required Offset globalPosition,
  required String workspaceId,
  required GitGraphState state,
  required GitCompareRef source,
}) async {
  if (!context.mounted) return;
  final l10n = context.l10n;
  final target = await showTpActionMenuOverlay<GitCompareSide>(
    context: context,
    globalPosition: globalPosition,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 160),
    transitionCurve: Curves.easeOutCubic,
    menuBuilder: (overlayContext, complete) {
      return _GitCompareTargetMenuOverlay(
        l10n: l10n,
        state: state,
        source: source,
        onSelect: (value) => complete(value),
      );
    },
  );
  if (target == null || !context.mounted) return;
  openGitCompareTab(
    context,
    workspaceId: workspaceId,
    spec: GitCompareSpec(repoRoot: state.repoRoot, left: source, right: target),
  );
}

class _GitCompareTargetMenuOverlay extends StatefulWidget {
  const _GitCompareTargetMenuOverlay({
    required this.l10n,
    required this.state,
    required this.source,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final GitGraphState state;
  final GitCompareRef source;
  final ValueChanged<GitCompareSide?> onSelect;

  @override
  State<_GitCompareTargetMenuOverlay> createState() =>
      _GitCompareTargetMenuOverlayState();
}

class _GitCompareTargetMenuOverlayState
    extends State<_GitCompareTargetMenuOverlay> {
  final _searchFocus = FocusNode(debugLabel: 'git-graph-compare-filter');
  String _filterQuery = '';

  bool get _showsSearchField => gitGraphActionMenuShowsSearchField(
    gitCompareTargetSearchableCount(widget.state),
  );

  @override
  void initState() {
    super.initState();
    if (_showsSearchField) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const minWidth = 200.0;
    final menuController = TpActionMenuController(TpPopoverController());
    final menuChildren = buildTpActionMenuChildren(
      context: context,
      specs: gitCompareTargetSpecs(
        l10n: widget.l10n,
        state: widget.state,
        source: widget.source,
        filterQuery: _filterQuery,
      ),
      menuController: menuController,
      onSelect: (value) => widget.onSelect(value as GitCompareSide?),
    );
    return DecoratedBox(
      decoration: TpActionMenuMetrics.panelDecoration(context),
      child: Padding(
        padding: TpActionMenuMetrics.panelPadding,
        child: GitGraphFilterableActionMenuPanel(
          minWidth: minWidth,
          showsSearchField: _showsSearchField,
          searchFocus: _searchFocus,
          filterHint: widget.l10n.gitGraphCompareFilterHint,
          onFilterChanged: (query) => setState(() => _filterQuery = query),
          menuChildren: menuChildren,
        ),
      ),
    );
  }
}
