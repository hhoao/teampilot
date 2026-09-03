import 'git_graph_lane_painter.dart';

abstract final class GitGraphColumns {
  static const double headerHeight = 30;
  static const double headerVerticalPadding = 6;
  static const double rowHeight = 32;
  static const double rowVerticalPadding = 4;
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

  static double graphWidthFor({required int maxLane}) =>
      (maxLane + 1) * GitGraphLanePainter.defaultLaneWidth;

  static String shortHash(String hash) =>
      hash.length <= 8 ? hash : hash.substring(0, 8);
}
