import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_compare.dart';
import '../git_compare/open_git_compare.dart';
import 'git_graph_menus.dart';

/// 弹层条目所属分区。
enum _RefSection { local, remote, tag }

class _RefEntry {
  const _RefEntry(this.section, this.name, {this.isCurrent = false});

  final _RefSection section;
  final String name;
  final bool isCurrent;
}

/// 分支 / 标签管理弹层：平铺列出本地分支、远程分支、标签三个分区，
/// 选中条目再弹动作子菜单（本地：checkout / 查看此分支历史 / 重命名 / 删除；
/// 远程：仅展示，checkout 暂不可用（v1）；标签：推送 / 删除）。写操作经
/// [GitGraphActionsController]。
class GitGraphRefsMenu extends StatefulWidget {
  const GitGraphRefsMenu({
    super.key,
    required this.state,
    required this.workspaceId,
  });

  final GitGraphState state;
  final String workspaceId;

  @override
  State<GitGraphRefsMenu> createState() => _GitGraphRefsMenuState();
}

class _GitGraphRefsMenuState extends State<GitGraphRefsMenu> {
  final GlobalKey _buttonKey = GlobalKey();

  Future<void> _openSubmenu(_RefEntry entry) async {
    final l10n = context.l10n;
    if (!mounted) return;
    final specs = switch (entry.section) {
      _RefSection.local => [
        TpActionMenuSpec.item(
          value: 'checkout',
          icon: Icons.check_circle_outline,
          label: l10n.gitGraphCheckoutBranch(entry.name),
          enabled: !entry.isCurrent,
        ),
        TpActionMenuSpec.item(
          value: 'history',
          icon: Icons.history,
          label: l10n.gitGraphViewBranchHistory,
        ),
        TpActionMenuSpec.item(
          value: 'compare',
          icon: Icons.difference_outlined,
          label: l10n.gitGraphCompareWith,
        ),
        TpActionMenuSpec.item(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: l10n.gitGraphRenameBranch,
        ),
        TpActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.gitGraphDeleteBranch(entry.name),
          destructive: true,
        ),
      ],
      // v1 仅列出远程分支，checkout 暂不可用。
      _RefSection.remote => [
        TpActionMenuSpec.item(
          icon: Icons.check_circle_outline,
          label: l10n.gitGraphCheckoutBranch(entry.name),
          enabled: false,
        ),
        TpActionMenuSpec.item(
          value: 'compare',
          icon: Icons.difference_outlined,
          label: l10n.gitGraphCompareWith,
        ),
      ],
      _RefSection.tag => [
        TpActionMenuSpec.item(
          value: 'push',
          icon: Icons.cloud_upload_outlined,
          label: l10n.gitGraphPushTag(entry.name),
        ),
        TpActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.gitGraphDeleteTag(entry.name),
          destructive: true,
        ),
        TpActionMenuSpec.item(
          value: 'compare',
          icon: Icons.difference_outlined,
          label: l10n.gitGraphCompareWith,
        ),
      ],
    };
    final action = await showTpActionMenuFromSpecs<String>(
      context: context,
      globalPosition: _buttonGlobalPosition(),
      specs: specs,
    );
    if (action == null || !mounted) return;
    final controller = GitGraphActionsController(
      cubit: context.read<GitGraphCubit>(),
    );
    switch (action) {
      case 'checkout':
        await controller.checkoutBranch(entry.name);
      case 'history':
        await context.read<GitGraphCubit>().setBranchFilter(entry.name);
      case 'rename':
        final newName = await showRenameBranchDialog(context, entry.name);
        if (newName == null || newName.isEmpty || !mounted) return;
        await controller.renameBranch(entry.name, newName);
      case 'push':
        await controller.pushTag(entry.name);
      case 'delete':
        await _confirmDelete(controller, entry);
      case 'compare':
        await _openCompareTargetMenu(entry);
    }
  }

  static const String _kWorkingTreeTarget = '__wt__';

  /// 二级目标菜单：首条工作区（当前分支），其后本地 / 远程 / 标签三分区；
  /// 源 ref 自身置灰。选中后打开 gitCompare 浮动 tab（left = 源，right = 目标）。
  /// 走 [showTpActionMenuOverlay] + [buildTpActionMenuChildren]：`FromSpecs`
  /// 变体不渲染 `TpActionMenuSpec.scroll` 分区（label 为 null 的空条目）。
  Future<void> _openCompareTargetMenu(_RefEntry source) async {
    if (!mounted) return;
    final l10n = context.l10n;
    final target = await showTpActionMenuOverlay<String>(
      context: context,
      globalPosition: _buttonGlobalPosition(),
      useRootNavigator: true,
      transitionDuration: const Duration(milliseconds: 160),
      transitionCurve: Curves.easeOutCubic,
      menuBuilder: (overlayContext, complete) {
        final children = buildTpActionMenuChildren(
          context: overlayContext,
          specs: _compareTargetSpecs(l10n, source),
          menuController: TpActionMenuController(TpPopoverController()),
          onSelect: (value) => complete(value as String?),
        );
        return DecoratedBox(
          decoration: TpActionMenuMetrics.panelDecoration(overlayContext),
          child: Padding(
            padding: TpActionMenuMetrics.panelPadding,
            child: TpActionMenuPanel(
              minWidth: 200,
              menuAnchorShell: true,
              children: children,
            ),
          ),
        );
      },
    );
    if (target == null || !mounted) return;
    openGitCompareTab(
      context,
      workspaceId: widget.workspaceId,
      spec: GitCompareSpec(
        repoRoot: widget.state.repoRoot,
        left: GitCompareRef(source.name),
        right: target == _kWorkingTreeTarget
            ? const GitCompareWorkingTree()
            : GitCompareRef(target),
      ),
    );
  }

  List<TpActionMenuSpec> _compareTargetSpecs(
    AppLocalizations l10n,
    _RefEntry source,
  ) {
    final state = widget.state;
    final locals = state.branches.where((b) => !b.isRemote);
    final remotes = state.branches.where((b) => b.isRemote);
    return [
      TpActionMenuSpec.item(
        value: _kWorkingTreeTarget,
        icon: Icons.difference_outlined,
        label: l10n.gitGraphCompareWorkingTree(
          state.currentBranch.isEmpty ? 'HEAD' : state.currentBranch,
        ),
      ),
      const TpActionMenuSpec.divider(),
      if (locals.isNotEmpty) ...[
        _sectionHeader(Icons.call_split, l10n.gitGraphLocalBranches),
        TpActionMenuSpec.scroll(children: [
          for (final branch in locals)
            TpActionMenuSpec.item(
              value: branch.name,
              icon: Icons.call_split_outlined,
              label: branch.name,
              enabled: branch.name != source.name,
            ),
        ]),
      ],
      if (remotes.isNotEmpty) ...[
        _sectionHeader(Icons.cloud_outlined, l10n.gitGraphRemoteBranches),
        TpActionMenuSpec.scroll(children: [
          for (final branch in remotes)
            TpActionMenuSpec.item(
              value: branch.name,
              icon: Icons.cloud_outlined,
              label: branch.name,
              enabled: branch.name != source.name,
            ),
        ]),
      ],
      if (state.tags.isNotEmpty) ...[
        _sectionHeader(Icons.sell_outlined, l10n.gitGraphTags),
        TpActionMenuSpec.scroll(children: [
          for (final tag in state.tags)
            TpActionMenuSpec.item(
              value: tag.name,
              icon: Icons.sell_outlined,
              label: tag.name,
              enabled: tag.name != source.name,
            ),
        ]),
      ],
    ];
  }

  Future<void> _confirmDelete(
    GitGraphActionsController controller,
    _RefEntry entry,
  ) async {
    final l10n = context.l10n;
    final confirmed = await confirmDangerAction(
      context,
      title: entry.section == _RefSection.tag
          ? l10n.gitGraphDeleteTagTitle
          : l10n.gitGraphDeleteBranchTitle,
      body: entry.section == _RefSection.tag
          ? l10n.gitGraphDeleteTagConfirmBody(entry.name)
          : l10n.gitGraphDeleteBranchConfirmBody(entry.name),
    );
    if (!confirmed || !mounted) return;
    if (entry.section == _RefSection.tag) {
      await controller.deleteTag(entry.name);
    } else {
      await controller.deleteBranch(entry.name);
    }
  }

  /// 子菜单锚定在按钮下方；拿不到按钮位置时回退到左上角附近。
  Offset _buttonGlobalPosition() {
    final button = _buttonKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (button is RenderBox && overlay is RenderBox && button.attached) {
      return button.localToGlobal(Offset.zero, ancestor: overlay);
    }
    return const Offset(48, 40);
  }

  List<TpActionMenuSpec> _buildSpecs(AppLocalizations l10n) {
    final locals = widget.state.branches.where((b) => !b.isRemote);
    final remotes = widget.state.branches.where((b) => b.isRemote);
    return [
      if (locals.isEmpty && remotes.isEmpty && widget.state.tags.isEmpty)
        TpActionMenuSpec.item(
          icon: Icons.account_tree_outlined,
          label: l10n.gitGraphBranchesTags,
          enabled: false,
        )
      else ...[
        if (locals.isNotEmpty) ...[
          _sectionHeader(Icons.call_split, l10n.gitGraphLocalBranches),
          TpActionMenuSpec.scroll(children: [
            for (final branch in locals)
              TpActionMenuSpec.item(
                value: _RefEntry(
                  _RefSection.local,
                  branch.name,
                  isCurrent: branch.isCurrent,
                ),
                icon: Icons.call_split_outlined,
                label: branch.name,
                selected: branch.isCurrent,
              ),
          ]),
        ],
        if (remotes.isNotEmpty) ...[
          _sectionHeader(Icons.cloud_outlined, l10n.gitGraphRemoteBranches),
          TpActionMenuSpec.scroll(children: [
            for (final branch in remotes)
              TpActionMenuSpec.item(
                value: _RefEntry(_RefSection.remote, branch.name),
                icon: Icons.cloud_outlined,
                label: branch.name,
              ),
          ]),
        ],
        if (widget.state.tags.isNotEmpty) ...[
          _sectionHeader(Icons.sell_outlined, l10n.gitGraphTags),
          TpActionMenuSpec.scroll(children: [
            for (final tag in widget.state.tags)
              TpActionMenuSpec.item(
                value: _RefEntry(_RefSection.tag, tag.name),
                icon: Icons.sell_outlined,
                label: tag.name,
              ),
          ]),
        ],
      ],
    ];
  }

  TpActionMenuSpec _sectionHeader(IconData icon, String label) =>
      TpActionMenuSpec.item(icon: icon, label: label, enabled: false);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.gitGraphBranchesTags,
      child: TpActionMenuIconAnchor(
        minWidth: 200,
        triggerBuilder: (context, controller) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            // 与相邻图标按钮同宽的紧凑入口，避免挤爆工具条。
            child: Container(
              key: _buttonKey,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.account_tree_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        },
        buildMenuChildren: (context, controller) =>
            buildTpActionMenuChildren(
              context: context,
              specs: _buildSpecs(l10n),
              menuController: controller,
              onSelect: (value) {
                if (value is _RefEntry) unawaited(_openSubmenu(value));
              },
            ),
      ),
    );
  }
}
