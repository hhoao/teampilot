import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_graph.dart';

/// 图面板顶部工具条：分支范围切换、fetch/pull/push、stash 弹层、搜索 + 模式、刷新。
/// 无状态：所有回调走 [GitGraphCubit] / [GitGraphActionsController]，不做 IO。
class GitGraphToolbar extends StatelessWidget {
  const GitGraphToolbar({super.key, required this.state});

  final GitGraphState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          _branchScopeButton(context),
          const SizedBox(width: 6),
          TpIconButton(
            icon: Icons.cloud_download_outlined,
            tooltip: l10n.gitGraphFetch,
            compact: true,
            onTap: () => _runAction(context, (actions) => actions.fetchAll()),
          ),
          TpIconButton(
            icon: Icons.arrow_downward_rounded,
            tooltip: l10n.gitGraphPull,
            compact: true,
            onTap: () => _runAction(context, (actions) => actions.pull()),
          ),
          TpIconButton(
            icon: Icons.arrow_upward_rounded,
            tooltip: l10n.gitGraphPush,
            compact: true,
            onTap: () => _runAction(context, (actions) => actions.push()),
          ),
          const SizedBox(width: 4),
          _stashMenu(context),
          const SizedBox(width: 8),
          Expanded(child: _searchField(context)),
          const SizedBox(width: 4),
          TpIconButton(
            icon: Icons.refresh_rounded,
            tooltip: l10n.gitGraphRefresh,
            compact: true,
            onTap: () => context.read<GitGraphCubit>().refresh(),
          ),
        ],
      ),
    );
  }

  /// all → `--all`；current → revisionRange `HEAD`。
  Widget _branchScopeButton(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: false, label: Text(l10n.gitGraphAllBranches)),
        ButtonSegment(value: true, label: Text(l10n.gitGraphCurrentBranch)),
      ],
      selected: {state.currentOnly},
      onSelectionChanged: (selection) => context
          .read<GitGraphCubit>()
          .setShowOnlyCurrentBranch(selection.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: WidgetStatePropertyAll(BorderSide(style: BorderStyle.none)),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        minimumSize: WidgetStatePropertyAll(Size(0, 26)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
      ),
    );
  }

  /// Stash 列表弹层。菜单项的 pop/apply/drop 动作由右键菜单任务接线。
  Widget _stashMenu(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.gitGraphStash,
      onSelected: (_) {},
      itemBuilder: (context) {
        if (state.stashList.isEmpty) {
          return [
            PopupMenuItem<String>(enabled: false, child: Text(l10n.gitGraphStash)),
          ];
        }
        return [
          for (final stash in state.stashList)
            PopupMenuItem<String>(
              value: stash.selector,
              child: Text(
                '${stash.selector} ${stash.subject}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              l10n.gitGraphStash,
              style: TpTextStyles.of(context).xs,
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = context.l10n;
    return TpInput(
      initialValue: state.searchQuery.isEmpty ? null : state.searchQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: l10n.gitGraphSearchHint,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 26),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _modeDropdown(context),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      onSubmitted: (query) =>
          context.read<GitGraphCubit>().search(query, state.searchMode),
    );
  }

  /// 模式三选：message / author / hash。切换后以最近一次提交的关键词重查。
  Widget _modeDropdown(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButton<GitSearchMode>(
      value: state.searchMode,
      underline: const SizedBox.shrink(),
      isDense: true,
      padding: EdgeInsets.zero,
      items: [
        for (final mode in GitSearchMode.values)
          DropdownMenuItem(
            value: mode,
            child: Text(
              _modeLabel(l10n, mode),
              style: TpTextStyles.of(context).xs,
            ),
          ),
      ],
      onChanged: (mode) {
        if (mode == null || mode == state.searchMode) return;
        context.read<GitGraphCubit>().search(state.searchQuery, mode);
      },
    );
  }

  String _modeLabel(AppLocalizations l10n, GitSearchMode mode) => switch (mode) {
    GitSearchMode.message => l10n.gitGraphSearchModeMessage,
    GitSearchMode.author => l10n.gitGraphSearchModeAuthor,
    GitSearchMode.hash => l10n.gitGraphSearchModeHash,
  };

  Future<void> _runAction(
    BuildContext context,
    Future<bool> Function(GitGraphActionsController actions) run,
  ) async {
    await run(
      GitGraphActionsController(cubit: context.read<GitGraphCubit>()),
    );
  }
}
