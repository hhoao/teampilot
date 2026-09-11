import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'git_graph_column_layout.dart';
import 'git_graph_columns.dart';
import 'git_graph_columns_row.dart';

/// 列头：标签行 + 可拖拽列宽分隔条 + 右键隐藏单列 / 列头。
///
/// 隐藏列与隐藏列头都直接走 [LayoutCubit]（面板树内必有其 scope）。
/// 列区排布走共享骨架 [GitGraphColumnsRow]，与提交行逐像素对齐。
///
/// 分隔条语义（跟随光标）：每条分隔条调整其**左侧**的固定列——向右拖
/// 加宽左列、分隔条右移；首条分隔条左侧是弹性描述列，改为反向调整其
/// 右侧的首列（向右拖收窄，分隔条仍跟随光标）；行尾边缘槽调整最后一列。
class GitGraphColumnHeader extends StatelessWidget {
  const GitGraphColumnHeader({super.key, required this.controller});

  final GitGraphColumnLayoutController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final layout = controller.layout;
        final colorScheme = Theme.of(context).colorScheme;
        final textStyle = TpTextStyles.of(
          context,
        ).mdColored(colorScheme.onSurfaceVariant);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: (details) => _showMenu(
            context,
            details.globalPosition,
            null,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: GitGraphColumns.horizontalPadding,
              vertical: GitGraphColumns.headerVerticalPadding,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: SizedBox(
              height: GitGraphColumns.headerHeight,
              child: GitGraphColumnsRow(
                layout: layout,
                gapBuilder: (id) => _handleFor(layout, id),
                graph: _HeaderLabel(
                  l10n.gitGraphColumnGraph,
                  style: textStyle,
                ),
                description: _HeaderLabel(
                  l10n.gitGraphColumnDescription,
                  style: textStyle,
                ),
                date: _HideableHeaderCell(
                  label: l10n.gitGraphColumnDate,
                  style: textStyle,
                  columnId: GitGraphColumnId.date,
                ),
                author: _HideableHeaderCell(
                  label: l10n.gitGraphColumnAuthor,
                  style: textStyle,
                  columnId: GitGraphColumnId.author,
                ),
                commit: _HideableHeaderCell(
                  label: l10n.gitGraphColumnCommit,
                  style: textStyle,
                  columnId: GitGraphColumnId.commit,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 间隙槽 → 拖拽条。目标列与方向见类注释。
  Widget _handleFor(GitGraphColumnLayout layout, GitGraphColumnId? id) {
    final visible = GitGraphColumnId.values
        .where((c) => !layout.isHidden(c))
        .toList(growable: false);
    if (visible.isEmpty) {
      return const SizedBox(width: GitGraphColumns.metaGap);
    }
    if (id == null) {
      // 行尾边缘：调整最后一列。
      return _ColumnResizeHandle(
        target: visible.last,
        invert: false,
        controller: controller,
      );
    }
    final index = visible.indexOf(id);
    if (index <= 0) {
      // 首条分隔条：左侧是弹性描述列 → 反向调整右侧首列。
      return _ColumnResizeHandle(
        target: id,
        invert: true,
        controller: controller,
      );
    }
    return _ColumnResizeHandle(
      target: visible[index - 1],
      invert: false,
      controller: controller,
    );
  }
}

String _columnLabel(AppLocalizations l10n, GitGraphColumnId id) =>
    switch (id) {
      GitGraphColumnId.date => l10n.gitGraphColumnDate,
      GitGraphColumnId.author => l10n.gitGraphColumnAuthor,
      GitGraphColumnId.commit => l10n.gitGraphColumnCommit,
    };

/// 可隐藏列的列头单元：右键弹「隐藏 <列>」+「隐藏列头」。
/// 宽度与间隙由共享骨架提供。
class _HideableHeaderCell extends StatelessWidget {
  const _HideableHeaderCell({
    required this.label,
    required this.style,
    required this.columnId,
  });

  final String label;
  final TextStyle style;
  final GitGraphColumnId columnId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) => _showMenu(
        context,
        details.globalPosition,
        columnId,
      ),
      child: SizedBox(
        key: ValueKey('git-graph-header-cell-${columnId.name}'),
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _HeaderLabel(label, style: style),
        ),
      ),
    );
  }
}

Future<void> _showMenu(
  BuildContext context,
  Offset position,
  GitGraphColumnId? columnId,
) async {
  final l10n = context.l10n;
  final cubit = context.read<LayoutCubit>();
  final choice = await showTpActionMenuFromSpecs<String>(
    context: context,
    globalPosition: position,
    specs: [
      if (columnId != null)
        TpActionMenuSpec.item(
          value: 'hide-column',
          icon: Icons.visibility_off_outlined,
          label: l10n.gitGraphHideColumn(_columnLabel(l10n, columnId)),
        ),
      if (columnId != null) const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'hide-header',
        icon: Icons.visibility_off_outlined,
        label: l10n.gitGraphHideColumnHeader,
      ),
    ],
  );
  if (choice == null) return;
  switch (choice) {
    case 'hide-column':
      final prefs = cubit.state.preferences.gitGraphColumns;
      cubit.setGitGraphColumns(
        prefs.copyWith(
          hiddenColumns: {...prefs.hiddenColumns, columnId!},
        ),
      );
    case 'hide-header':
      cubit.setGitGraphHeaderVisible(false);
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.label, {required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
    style: style,
  );
}

/// 分隔条：拖动实时调整 [target] 列宽，松手持久化。
///
/// 视觉反馈：平时 1px 浅色刻度；悬停 / 拖拽时 2.5px 主色竖线。
class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.target,
    required this.invert,
    required this.controller,
  });

  /// 本分隔条调整的列（见 [GitGraphColumnHeader] 类注释的语义）。
  final GitGraphColumnId target;
  final bool invert;
  final GitGraphColumnLayoutController controller;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.controller.resizingColumn == widget.target;
    final engaged = active || _hovered;
    return SizedBox(
      width: GitGraphColumns.metaGap,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => widget.controller.beginResize(
            column: widget.target,
            invert: widget.invert,
            globalDx: details.globalPosition.dx,
          ),
          onHorizontalDragUpdate: (details) =>
              widget.controller.updateResize(details.globalPosition.dx),
          onHorizontalDragEnd: (_) => widget.controller.commit(context),
          onHorizontalDragCancel: () => widget.controller.commit(context),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: engaged ? 2.5 : 1,
              height: double.infinity,
              color: engaged
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
