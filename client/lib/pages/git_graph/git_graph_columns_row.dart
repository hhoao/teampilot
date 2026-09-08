import 'package:flutter/material.dart';

import '../../models/layout_preferences.dart';
import 'git_graph_column_layout.dart';
import 'git_graph_columns.dart';

/// 列区骨架：图槽 + 描述 Expanded + 元数据列（隐藏列跳过）+ 行尾间隙槽。
///
/// 列头 / 提交行 / 未提交伪行**共用本骨架**——列边界对齐由构造保证，
/// 不靠三处布局代码各自保持一致。元数据列为刚性宽（描述列吃剩余空间）；
/// 整行放不下时按同一算法把元数据列等比压向下限（列头与行同步收缩，
/// 依旧对齐）。
class GitGraphColumnsRow extends StatelessWidget {
  const GitGraphColumnsRow({
    super.key,
    required this.layout,
    required this.graph,
    required this.description,
    required this.date,
    required this.author,
    required this.commit,
    this.gapBuilder,
  });

  final GitGraphColumnLayout layout;

  /// 图槽内容（列头标签 / 行的 lane painter / 伪行图标）。
  final Widget graph;

  /// 描述列内容；占据全部剩余宽度。
  final Widget description;
  final Widget date;
  final Widget author;
  final Widget commit;

  /// 列间隙槽构造器；[GitGraphColumnId] 为其后紧跟的列，null 为行尾
  /// 边缘槽（列头在首列前与行尾各放一条拖拽条）。缺省为
  /// [GitGraphColumns.metaGap] 宽空槽。
  final Widget Function(GitGraphColumnId? id)? gapBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = GitGraphColumnId.values
            .where((id) => !layout.isHidden(id))
            .toList(growable: false);
        final widths = _effectiveWidths(visible, constraints.maxWidth);
        Widget gap(GitGraphColumnId? id) =>
            gapBuilder?.call(id) ??
            const SizedBox(width: GitGraphColumns.metaGap);
        return Row(
          children: [
            SizedBox(width: layout.graphWidth, child: graph),
            const SizedBox(width: GitGraphColumns.afterGraphGap),
            Expanded(child: description),
            for (final id in visible) ...[
              gap(id),
              SizedBox(width: widths[id], child: _childFor(id)),
            ],
            gap(null),
          ],
        );
      },
    );
  }

  Widget _childFor(GitGraphColumnId id) => switch (id) {
    GitGraphColumnId.date => date,
    GitGraphColumnId.author => author,
    GitGraphColumnId.commit => commit,
  };

  /// 空间不足时把元数据列等比压向 [GitGraphColumnPrefs.minColumnWidth]：
  /// 先算总超出量，再按「超出量 / 可压总量」统一收缩比例，保证列头与
  /// 行在任意宽度下收缩结果一致。
  Map<GitGraphColumnId, double> _effectiveWidths(
    List<GitGraphColumnId> visible,
    double maxWidth,
  ) {
    final natural = {
      for (final id in visible) id: layout.widthOf(id),
    };
    final fixed = layout.graphWidth +
        GitGraphColumns.afterGraphGap +
        (visible.length + 1) * GitGraphColumns.metaGap;
    final available = maxWidth - fixed;
    final naturalSum = natural.values.fold(0.0, (a, b) => a + b);
    if (naturalSum <= available || visible.isEmpty) return natural;

    final excess = naturalSum - available;
    final shrinkable =
        naturalSum - visible.length * GitGraphColumnPrefs.minColumnWidth;
    final k = shrinkable <= 0 || excess >= shrinkable
        ? 1.0
        : excess / shrinkable;
    final floored = {
      for (final id in visible)
        id: natural[id]! -
            k * (natural[id]! - GitGraphColumnPrefs.minColumnWidth),
    };
    final flooredSum = floored.values.fold(0.0, (a, b) => a + b);
    if (flooredSum <= available) return floored;
    // 触底仍放不下（极窄）：按比例整体压缩，保证永不溢出。
    final scale = available / naturalSum;
    return {
      for (final id in visible) id: natural[id]! * (scale < 0 ? 0 : scale),
    };
  }
}
