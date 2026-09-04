import 'git_graph_lane_painter.dart';

abstract final class GitGraphColumns {
  static const double headerHeight = 30;
  static const double headerVerticalPadding = 6;
  static const double rowHeight = 32;
  static const double rowVerticalPadding = 4;
  /// 提交行整行高度（含上下呼吸留白）。连线画满整行，跨行才能无缝衔接。
  static const double rowTileHeight = rowHeight + 2 * rowVerticalPadding;
  /// Horizontal inset for header + rows (graph left edge + trailing meta).
  static const double horizontalPadding = 12;
  static const double afterGraphGap = 8;
  static const double metaGap = 8;
  static const double commitWidth = 72; // ~8 monospace chars
  static const double dateMinWidth = 88;
  static const int descriptionFlex = 10;
  static const int dateFlex = 2;
  static const int authorFlex = 2;
  static const int refsFlex = 3;

  /// 图形区宽度：容纳 slot 的 x 位置再加右侧半 lane。
  /// 偶数 slot（lane 中心）占 (slot ~/ 2 + 1) 个 lane 宽；奇数 slot
  /// （lane 间空隙）再多半 lane。
  static double graphWidthFor({required int maxSlot}) =>
      ((maxSlot >> 1) + 1) * GitGraphLanePainter.defaultLaneWidth +
      (maxSlot & 1) * GitGraphLanePainter.defaultLaneWidth / 2;

  static String shortHash(String hash) =>
      hash.length <= 8 ? hash : hash.substring(0, 8);
}
