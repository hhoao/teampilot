import 'git_graph_lane_painter.dart';

abstract final class GitGraphColumns {
  static const double headerHeight = 26;
  static const double rowHeight = 28;
  static const double trailingPadding = 12;
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
