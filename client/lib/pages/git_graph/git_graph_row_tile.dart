import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/git_graph.dart';
import 'git_graph_lane_painter.dart';

/// 提交图单行：graph 片元 + 文本列。spacer 行用 [GitGraphSpacerTile]。
class GitGraphRowTile extends StatelessWidget {
  const GitGraphRowTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
    this.onSecondaryTapUp,
    this.onLongPress,
    this.palette = defaultPalette,
    this.dateFormat,
  });

  static const List<Color> defaultPalette = [
    Color(0xFF4C8DFF),
    Color(0xFF54C08A),
    Color(0xFFE0A63F),
    Color(0xFFD96C6C),
    Color(0xFF9B7BE0),
    Color(0xFF4FB6C9),
    Color(0xFFC97BB5),
    Color(0xFF8FA83F),
    Color(0xFFB08B5C),
    Color(0xFF7C93F0),
    Color(0xFF5FBF9E),
    Color(0xFFDD8A4D),
  ];

  final GitCommitRow row;
  final bool selected;
  final VoidCallback onTap;
  /// 桌面右键（菜单在调用方接线）。
  final void Function(TapDownDetails)? onSecondaryTapUp;

  /// 移动端长按（Android SSH 场景）。
  final GestureTapCallback? onLongPress;
  final List<Color> palette;
  final DateFormat? dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = selected ? cs.primary.withValues(alpha: 0.12) : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapUp: onSecondaryTapUp == null
          ? null
          : (details) => onSecondaryTapUp!(
                TapDownDetails(
                  globalPosition: details.globalPosition,
                  localPosition: details.localPosition,
                  kind: details.kind,
                ),
              ),
      child: Container(
        height: 28,
        color: bg,
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          children: [
            SizedBox(
              width: _graphWidth(),
              child: CustomPaint(
                size: const Size(double.infinity, 28),
                painter: GitGraphLanePainter(
                  edges: row.edges,
                  node: row.node,
                  palette: palette,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ...[for (final r in row.refs) _RefChip(decoration: r)],
            Expanded(
              child: Text(
                row.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTextStyles.of(context).sm,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              row.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
            ),
            const SizedBox(width: 10),
            Text(
              (dateFormat ?? DateFormat('MM/dd HH:mm'))
                  .format(row.authorDate.toLocal()),
              style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  double _graphWidth() {
    final maxLane = [
      for (final e in row.edges) e.fromLane,
      for (final e in row.edges) e.toLane,
      row.node.lane,
    ].reduce((a, b) => a > b ? a : b);
    return (maxLane + 1) * GitGraphLanePainter.defaultLaneWidth;
  }
}

class _RefChip extends StatelessWidget {
  const _RefChip({required this.decoration});
  final GitRefDecoration decoration;

  @override
  Widget build(BuildContext context) {
    final colors = switch (decoration.kind) {
      GitRefDecorationKind.head => Colors.amber,
      GitRefDecorationKind.localBranch => Colors.lightBlueAccent,
      GitRefDecorationKind.remoteBranch => Colors.tealAccent.shade200,
      GitRefDecorationKind.tag => Colors.purpleAccent,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: colors.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.withValues(alpha: 0.55)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            switch (decoration.kind) {
              GitRefDecorationKind.head => Icons.push_pin_outlined,
              GitRefDecorationKind.tag => Icons.sell_outlined,
              _ => Icons.call_split_rounded,
            },
            size: 9,
            color: colors,
          ),
          const SizedBox(width: 2),
          Text(
            decoration.name.isEmpty ? 'HEAD' : decoration.name,
            style: TpTextStyles.of(context).xsColored(colors),
          ),
        ]),
      ),
    );
  }
}

/// 无提交的纯连线行（半高）。
class GitGraphSpacerTile extends StatelessWidget {
  const GitGraphSpacerTile({
    super.key,
    required this.row,
    this.palette = GitGraphRowTile.defaultPalette,
  });

  final GitGraphRow row;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: 16,
        child: CustomPaint(
          size: const Size(double.infinity, 16),
          painter: GitGraphLanePainter(edges: row.edges, palette: palette),
        ),
      ),
    );
  }
}
