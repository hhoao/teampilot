import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_compare.dart';
import 'git_graph_compare_targets.dart';
import 'git_graph_filterable_action_menu_panel.dart';
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
/// 选中条目再弹动作子菜单（本地：checkout / 查看此分支历史 / 比较 / 重命名 /
/// 删除；远程：checkout（创建本地跟踪分支）/ 历史 / 比较 / 删除（push
/// --delete）；标签：检出 / 历史 / 推送 / 删除）。写操作经
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
  final _popoverController = TpPopoverController();
  final _searchFocus = FocusNode(debugLabel: 'git-graph-refs-filter');
  String _filterQuery = '';

  int get _totalRefCount =>
      widget.state.branches.length + widget.state.tags.length;

  bool get _showsSearchField => gitGraphActionMenuShowsSearchField(_totalRefCount);

  @override
  void initState() {
    super.initState();
    _popoverController.addListener(_onPopoverChanged);
  }

  @override
  void dispose() {
    _popoverController.removeListener(_onPopoverChanged);
    _popoverController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onPopoverChanged() {
    if (_popoverController.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_popoverController.isOpen) return;
        if (_showsSearchField) _searchFocus.requestFocus();
      });
      return;
    }
    if (_filterQuery.isNotEmpty) {
      setState(() => _filterQuery = '');
    }
  }

  TpActionMenuController get _menuController =>
      TpActionMenuController(_popoverController);

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
      // 远程：checkout 创建本地跟踪分支，删除走 push --delete。
      _RefSection.remote => [
        TpActionMenuSpec.item(
          value: 'checkout',
          icon: Icons.check_circle_outline,
          label: l10n.gitGraphCheckoutBranch(entry.name),
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
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.gitGraphDeleteBranch(entry.name),
          destructive: true,
        ),
      ],
      _RefSection.tag => [
        TpActionMenuSpec.item(
          value: 'checkout',
          icon: Icons.check_circle_outline,
          label: l10n.gitGraphCheckoutBranch(entry.name),
        ),
        TpActionMenuSpec.item(
          value: 'history',
          icon: Icons.history,
          label: l10n.gitGraphViewTagHistory,
        ),
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
        switch (entry.section) {
          case _RefSection.local:
            await controller.checkoutBranch(entry.name);
          case _RefSection.remote:
            await controller.checkoutRemoteBranch(entry.name);
          case _RefSection.tag:
            await controller.checkoutTag(entry.name);
        }
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
        await showGitCompareTargetMenu(
          context: context,
          globalPosition: _buttonGlobalPosition(),
          workspaceId: widget.workspaceId,
          state: widget.state,
          source: GitCompareRef(entry.name),
        );
    }
  }

  Future<void> _confirmDelete(
    GitGraphActionsController controller,
    _RefEntry entry,
  ) async {
    final l10n = context.l10n;
    final (title, body) = switch (entry.section) {
      _RefSection.tag => (
        l10n.gitGraphDeleteTagTitle,
        l10n.gitGraphDeleteTagConfirmBody(entry.name),
      ),
      _RefSection.remote => (
        l10n.gitGraphDeleteRemoteBranchTitle,
        l10n.gitGraphDeleteRemoteBranchConfirmBody(entry.name),
      ),
      _RefSection.local => (
        l10n.gitGraphDeleteBranchTitle,
        l10n.gitGraphDeleteBranchConfirmBody(entry.name),
      ),
    };
    final confirmed = await confirmDangerAction(
      context,
      title: title,
      body: body,
    );
    if (!confirmed || !mounted) return;
    switch (entry.section) {
      case _RefSection.tag:
        await controller.deleteTag(entry.name);
      case _RefSection.remote:
        await controller.deleteRemoteBranch(entry.name);
      case _RefSection.local:
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

  bool _matchesFilter(String name) {
    final needle = _filterQuery.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle);
  }

  List<TpActionMenuSpec> _buildSpecs(AppLocalizations l10n) {
    final locals = widget.state.branches
        .where((b) => !b.isRemote && _matchesFilter(b.name));
    final remotes = widget.state.branches
        .where((b) => b.isRemote && _matchesFilter(b.name));
    final tags = widget.state.tags.where((t) => _matchesFilter(t.name));
    final hasActiveFilter = _filterQuery.trim().isNotEmpty;
    return [
      if (locals.isEmpty &&
          remotes.isEmpty &&
          tags.isEmpty &&
          !hasActiveFilter)
        TpActionMenuSpec.item(
          icon: Icons.account_tree_outlined,
          label: l10n.gitGraphBranchesTags,
          enabled: false,
        )
      else if (locals.isEmpty && remotes.isEmpty && tags.isEmpty)
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
                  value: _RefEntry(
                    _RefSection.local,
                    branch.name,
                    isCurrent: branch.isCurrent,
                  ),
                  icon: Icons.call_split_outlined,
                  label: branch.name,
                  selected: branch.isCurrent,
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
                  value: _RefEntry(_RefSection.remote, branch.name),
                  icon: Icons.cloud_outlined,
                  label: branch.name,
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
                  value: _RefEntry(_RefSection.tag, tag.name),
                  icon: Icons.sell_outlined,
                  label: tag.name,
                ),
            ],
          ),
        ],
      ],
    ];
  }

  TpActionMenuSpec _sectionHeader(IconData icon, String label) =>
      TpActionMenuSpec.item(icon: icon, label: label, enabled: false);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final menuController = _menuController;
    return Tooltip(
      message: l10n.gitGraphBranchesTags,
      child: TpPopover(
        controller: _popoverController,
        anchor: const TpAnchor(
          childAlignment: Alignment.topLeft,
          overlayAlignment: Alignment.bottomLeft,
          offset: Offset(0, 4),
        ),
        decoration: TpActionMenuMetrics.panelDecoration(context),
        padding: TpActionMenuMetrics.panelPadding,
        popover: (ctx) => GitGraphFilterableActionMenuPanel(
          minWidth: 200,
          showsSearchField: _showsSearchField,
          searchFocus: _searchFocus,
          filterHint: l10n.gitGraphRefsFilterHint,
          onFilterChanged: (query) => setState(() => _filterQuery = query),
          menuChildren: buildTpActionMenuChildren(
            context: ctx,
            specs: _buildSpecs(l10n),
            menuController: menuController,
            onSelect: (value) {
              if (value is _RefEntry) unawaited(_openSubmenu(value));
            },
          ),
        ),
        child: TpButton(
          key: _buttonKey,
          variant: TpButtonVariant.outline,
          size: TpControlSize.small,
          onPressed: _popoverController.toggle,
          child: Icon(
            Icons.account_tree_outlined,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
