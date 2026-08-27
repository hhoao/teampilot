import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_graph.dart';
import 'git_graph_menus.dart';
import 'git_graph_refs_menu.dart';

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
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _branchScopeButton(context),
                  if (state.branchFilter != null) ...[
                    const SizedBox(width: 6),
                    _branchFilterChip(context),
                  ],
                  const SizedBox(width: 6),
                  TpIconButton(
                    icon: Icons.cloud_download_outlined,
                    tooltip: l10n.gitGraphFetch,
                    compact: true,
                    onTap: () =>
                        _runAction(context, (actions) => actions.fetchAll()),
                  ),
                  TpIconButton(
                    icon: Icons.arrow_downward_rounded,
                    tooltip: l10n.gitGraphPull,
                    compact: true,
                    onTap: () =>
                        _runAction(context, (actions) => actions.pull()),
                  ),
                  TpIconButton(
                    icon: Icons.arrow_upward_rounded,
                    tooltip: l10n.gitGraphPush,
                    compact: true,
                    onTap: () =>
                        _runAction(context, (actions) => actions.push()),
                  ),
                  const SizedBox(width: 4),
                  _StashMenu(state: state),
                  const SizedBox(width: 4),
                  GitGraphRefsMenu(state: state),
                ],
              ),
            ),
          ),
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
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: WidgetStatePropertyAll(BorderSide(style: BorderStyle.none)),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        minimumSize: WidgetStatePropertyAll(Size(0, 26)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        textStyle: WidgetStatePropertyAll(TpTextStyles.of(context).xs),
      ),
    );
  }

  /// 分支历史过滤 chip：高亮展示被查看历史的分支名，点关闭清除过滤。
  Widget _branchFilterChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.gitGraphViewBranchHistory,
      child: Container(
        key: const ValueKey('git-graph-branch-filter-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 14,
              color: cs.onPrimaryContainer,
            ),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                state.branchFilter!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TpTextStyles.of(
                  context,
                ).xsColored(cs.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.read<GitGraphCubit>().setBranchFilter(null),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: cs.onPrimaryContainer,
              ),
            ),
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
  /// 紧凑无框 [TpSelect]，嵌在搜索框尾部；固定宽度保证弹层条目不省略。
  Widget _modeDropdown(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 108,
      child: TpSelect<GitSearchMode>(
        key: ValueKey(state.searchMode),
        items: GitSearchMode.values,
        initialItem: state.searchMode,
        searchable: false,
        itemLabel: (mode) => _modeLabel(l10n, mode),
        closedHeaderPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        expandedHeaderPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 2,
        ),
        listItemPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: TpSelectDecorations.themed(
          context,
          closedFillColor: Colors.transparent,
          closedBorder: const Border(),
          buttonHoverColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.04),
          headerStyle: TpTextStyles.of(context).xs,
          listItemStyle: TpTextStyles.of(context).sm,
          suffixIconSize: context.tpIconSizes.sm,
        ),
        onChanged: (mode) {
          if (mode == null || mode == state.searchMode) return;
          context.read<GitGraphCubit>().search(state.searchQuery, mode);
        },
      ),
    );
  }

  String _modeLabel(AppLocalizations l10n, GitSearchMode mode) =>
      switch (mode) {
        GitSearchMode.message => l10n.gitGraphSearchModeMessage,
        GitSearchMode.author => l10n.gitGraphSearchModeAuthor,
        GitSearchMode.hash => l10n.gitGraphSearchModeHash,
      };

  Future<void> _runAction(
    BuildContext context,
    Future<bool> Function(GitGraphActionsController actions) run,
  ) async {
    await run(GitGraphActionsController(cubit: context.read<GitGraphCubit>()));
  }
}

/// Stash 弹层：主菜单列出 `stashList`，选中条目再弹 Pop/Applly/Drop 子菜单
/// （Drop 走 [confirmDangerAction]）；v1 不做 stash 创建（仍走终端）。
class _StashMenu extends StatefulWidget {
  const _StashMenu({required this.state});

  final GitGraphState state;

  @override
  State<_StashMenu> createState() => _StashMenuState();
}

class _StashMenuState extends State<_StashMenu> {
  final GlobalKey _buttonKey = GlobalKey();

  Future<void> _openSubmenu(GitStashEntry entry) async {
    final l10n = context.l10n;
    if (!mounted) return;
    final action = await showTpActionMenuFromSpecs<String>(
      context: context,
      globalPosition: _buttonGlobalPosition(),
      specs: [
        TpActionMenuSpec.item(
          value: 'pop',
          icon: Icons.unarchive,
          label: l10n.gitGraphStashPop,
        ),
        TpActionMenuSpec.item(
          value: 'apply',
          icon: Icons.move_to_inbox,
          label: l10n.gitGraphStashApply,
        ),
        TpActionMenuSpec.item(
          value: 'drop',
          icon: Icons.delete_outline,
          label: l10n.gitGraphStashDrop,
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    final controller = GitGraphActionsController(
      cubit: context.read<GitGraphCubit>(),
    );
    switch (action) {
      case 'pop':
        await controller.stashPop(ref: entry.selector);
      case 'apply':
        await controller.stashApply(ref: entry.selector);
      case 'drop':
        final confirmed = await confirmDangerAction(
          context,
          title: l10n.gitGraphStashDrop,
          body: l10n.gitGraphStashDropConfirmBody(entry.selector),
        );
        if (!confirmed || !mounted) return;
        await controller.stashDrop(ref: entry.selector);
    }
  }

  /// 子菜单锚定在 stash 按钮下方；拿不到按钮位置时回退到左上角附近。
  Offset _buttonGlobalPosition() {
    final button = _buttonKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (button is RenderBox && overlay is RenderBox && button.attached) {
      return button.localToGlobal(Offset.zero, ancestor: overlay);
    }
    return const Offset(48, 40);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.gitGraphStash,
      child: TpActionMenuIconAnchor(
        minWidth: 220,
        triggerBuilder: (context, controller) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Container(
              key: _buttonKey,
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
                  Text(l10n.gitGraphStash, style: TpTextStyles.of(context).xs),
                  const Icon(Icons.arrow_drop_down_rounded, size: 14),
                ],
              ),
            ),
          );
        },
        buildMenuChildren: (context, controller) {
          if (widget.state.stashList.isEmpty) {
            return buildTpActionMenuChildren(
              context: context,
              specs: [
                TpActionMenuSpec.item(
                  icon: Icons.inventory_2_outlined,
                  label: l10n.gitGraphStash,
                  enabled: false,
                ),
              ],
              menuController: controller,
              onSelect: (_) {},
            );
          }
          return buildTpActionMenuChildren(
            context: context,
            specs: [
              TpActionMenuSpec.scroll(children: [
                for (final stash in widget.state.stashList)
                  TpActionMenuSpec.item(
                    value: stash,
                    icon: Icons.inventory_2_outlined,
                    label: '${stash.selector} ${stash.subject}',
                  ),
              ]),
            ],
            menuController: controller,
            onSelect: (value) {
              if (value is GitStashEntry) unawaited(_openSubmenu(value));
            },
          );
        },
      ),
    );
  }
}
