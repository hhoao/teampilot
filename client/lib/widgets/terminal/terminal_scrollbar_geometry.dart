/// GtkAdjustment / VTE scrollbar math for [TerminalHistoryScrollbar].
///
/// Ported from flutter_alacritty's example (not library API).
///
/// VTE model (`vte_terminal` + `GtkAdjustment`):
/// - `upper` = total lines in buffer (`history_size + viewport_rows`)
/// - `page_size` = visible rows (`viewport_rows`)
/// - `value` ∈ [0, `history_size`] where `value` = `display_offset` (+ fraction)
/// - `value == 0` → live bottom; thumb sits at the **bottom** of the track
/// - `value == history_size` → top of scrollback; thumb at the **top** of the track
/// - thumb height ratio = `page_size / upper`
class TerminalScrollbarGeometry {
  const TerminalScrollbarGeometry({
    required this.historySize,
    required this.viewportRows,
    required this.scrollOffsetLines,
    required this.trackHeight,
    this.minThumbFraction = 0.08,
  });

  /// Snap to [scrollToBottom]/[scrollToTop] when within this fraction of an edge.
  static const double edgeSnapFraction = 0.02;

  final int historySize;
  final int viewportRows;
  final double scrollOffsetLines;
  final double trackHeight;
  final double minThumbFraction;

  bool get visible => historySize > 0 && trackHeight > 0;

  /// Gtk `value / (upper - page_size)` inverted for thumb placement:
  /// `1.0` = live bottom (thumb at track bottom), `0.0` = history top.
  double get positionFraction {
    if (historySize <= 0) return 1.0;
    final value = (scrollOffsetLines / historySize).clamp(0.0, 1.0);
    return 1.0 - value;
  }

  double get thumbFraction {
    if (historySize <= 0) return 1.0;
    final viewport = viewportRows.clamp(1, historySize + viewportRows);
    return (viewport / (historySize + viewport)).clamp(minThumbFraction, 1.0);
  }

  double get thumbHeight => trackHeight * thumbFraction;

  double get thumbTop {
    return thumbTopAt(positionFraction);
  }

  double thumbTopAt(double fraction) {
    final usable = trackHeight - thumbHeight;
    if (usable <= 0) return 0;
    return fraction.clamp(0.0, 1.0) * usable;
  }

  /// Map pointer Y on the track to [positionFraction] (NOT inverted).
  ///
  /// Uses thumb-leading-edge in the usable range — same as GtkRange mapping
  /// `value = thumb_leading / usable * max_value`.
  static double positionFractionFromTrackDy({
    required double localDy,
    required double trackHeight,
    required double thumbHeight,
  }) {
    final usable = trackHeight - thumbHeight;
    if (usable <= 0) return 1.0;
    final leading = (localDy - thumbHeight / 2).clamp(0.0, usable);
    return (leading / usable).clamp(0.0, 1.0);
  }

  /// Gtk `value` from [positionFraction].
  double scrollOffsetForPosition(double positionFraction) =>
      (1.0 - positionFraction.clamp(0.0, 1.0)) * historySize;

  bool isNearLiveBottom(double positionFraction) =>
      positionFraction >= 1.0 - edgeSnapFraction;

  bool isNearHistoryTop(double positionFraction) =>
      positionFraction <= edgeSnapFraction;
}
