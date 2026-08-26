import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
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
/// 选中条目再弹动作子菜单（本地：checkout / 重命名 / 删除；远程：仅展示，
/// checkout 暂不可用（v1）；标签：推送 / 删除）。写操作经
/// [GitGraphActionsController]。
class GitGraphRefsMenu extends StatefulWidget {
  const GitGraphRefsMenu({super.key, required this.state});

  final GitGraphState state;

  @override
  State<GitGraphRefsMenu> createState() => _GitGraphRefsMenuState();
}

class _GitGraphRefsMenuState extends State<GitGraphRefsMenu> {
  final GlobalKey _buttonKey = GlobalKey();

  Future<void> _openSubmenu(_RefEntry entry) async {
    final l10n = context.l10n;
    final position = _buttonPosition();
    if (!mounted) return;
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: switch (entry.section) {
        _RefSection.local => [
          PopupMenuItem<String>(
            value: 'checkout',
            enabled: !entry.isCurrent,
            child: Text(l10n.gitGraphCheckoutBranch(entry.name)),
          ),
          PopupMenuItem<String>(
            value: 'rename',
            child: Text(l10n.gitGraphRenameBranch),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(l10n.gitGraphDeleteBranch(entry.name)),
          ),
        ],
        // v1 仅列出远程分支，checkout 暂不可用。
        _RefSection.remote => [
          PopupMenuItem<String>(
            enabled: false,
            child: Text(l10n.gitGraphCheckoutBranch(entry.name)),
          ),
        ],
        _RefSection.tag => [
          PopupMenuItem<String>(
            value: 'push',
            child: Text(l10n.gitGraphPushTag(entry.name)),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(l10n.gitGraphDeleteTag(entry.name)),
          ),
        ],
      },
    );
    if (action == null || !mounted) return;
    final controller = GitGraphActionsController(
      cubit: context.read<GitGraphCubit>(),
    );
    switch (action) {
      case 'checkout':
        await controller.checkoutBranch(entry.name);
      case 'rename':
        final newName = await showRenameBranchDialog(context, entry.name);
        if (newName == null || newName.isEmpty || !mounted) return;
        await controller.renameBranch(entry.name, newName);
      case 'push':
        await controller.pushTag(entry.name);
      case 'delete':
        await _confirmDelete(controller, entry);
    }
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
  RelativeRect _buttonPosition() {
    final button = _buttonKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (button is RenderBox && overlay is RenderBox && button.attached) {
      final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
      return RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - button.size.width,
        topLeft.dy + 1,
      );
    }
    return const RelativeRect.fromLTRB(48, 40, 48, 40);
  }

  List<PopupMenuEntry<_RefEntry>> _buildItems(AppLocalizations l10n) {
    final locals = widget.state.branches.where((b) => !b.isRemote);
    final remotes = widget.state.branches.where((b) => b.isRemote);
    return [
      if (locals.isEmpty && remotes.isEmpty && widget.state.tags.isEmpty)
        PopupMenuItem<_RefEntry>(
          enabled: false,
          child: Text(l10n.gitGraphBranchesTags),
        )
      else ...[
        if (locals.isNotEmpty) ...[
          _sectionHeader(l10n.gitGraphLocalBranches),
          for (final branch in locals)
            PopupMenuItem<_RefEntry>(
              value: _RefEntry(
                _RefSection.local,
                branch.name,
                isCurrent: branch.isCurrent,
              ),
              height: 34,
              child: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        if (remotes.isNotEmpty) ...[
          _sectionHeader(l10n.gitGraphRemoteBranches),
          for (final branch in remotes)
            PopupMenuItem<_RefEntry>(
              value: _RefEntry(_RefSection.remote, branch.name),
              height: 34,
              child: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        if (widget.state.tags.isNotEmpty) ...[
          _sectionHeader(l10n.gitGraphTags),
          for (final tag in widget.state.tags)
            PopupMenuItem<_RefEntry>(
              value: _RefEntry(_RefSection.tag, tag.name),
              height: 34,
              child: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ],
    ];
  }

  PopupMenuEntry<_RefEntry> _sectionHeader(String label) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<_RefEntry>(
      enabled: false,
      height: 30,
      child: Text(label, style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<_RefEntry>(
      tooltip: l10n.gitGraphBranchesTags,
      onSelected: (entry) => unawaited(_openSubmenu(entry)),
      itemBuilder: (context) => _buildItems(l10n),
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
  }
}
