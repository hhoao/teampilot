import 'thread_turns.dart';

class TurnVisibleRange {
  const TurnVisibleRange({
    required this.firstIndex,
    required this.lastIndex,
    required this.paddingTop,
    required this.paddingBottom,
  });
  final int firstIndex;
  final int lastIndex;
  final double paddingTop;
  final double paddingBottom;
}

class TurnHeightCache {
  TurnHeightCache({this.estimate = 200});

  final double estimate;
  final Map<String, double> _measured = {};

  double heightOf(String turnId) => _measured[turnId] ?? estimate;

  bool isMeasured(String turnId) => _measured.containsKey(turnId);

  void setMeasured(String turnId, double height) {
    if (height <= 0) return;
    _measured[turnId] = height;
  }

  void invalidate(String turnId) => _measured.remove(turnId);

  void invalidateAll() => _measured.clear();

  double totalExtent(List<ThreadTurn> turns) {
    var sum = 0.0;
    for (final t in turns) {
      sum += heightOf(t.id);
    }
    return sum;
  }

  /// Cumulative height of turns[0..index) (exclusive end).
  double offsetBefore(List<ThreadTurn> turns, int index) {
    var sum = 0.0;
    final end = index.clamp(0, turns.length);
    for (var i = 0; i < end; i++) {
      sum += heightOf(turns[i].id);
    }
    return sum;
  }

  TurnVisibleRange visibleRange({
    required List<ThreadTurn> turns,
    required double scrollPixels,
    required double viewportHeight,
    required int overscan,
  }) {
    if (turns.isEmpty) {
      return const TurnVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: 0,
      );
    }
    final top = scrollPixels < 0 ? 0.0 : scrollPixels;
    final bottom = top + viewportHeight;
    var acc = 0.0;
    var first = 0;
    var last = turns.length - 1;
    var foundFirst = false;
    for (var i = 0; i < turns.length; i++) {
      final h = heightOf(turns[i].id);
      final turnBottom = acc + h;
      if (!foundFirst && turnBottom > top) {
        first = i;
        foundFirst = true;
      }
      if (acc < bottom) {
        last = i;
      }
      acc = turnBottom;
    }
    first = (first - overscan).clamp(0, turns.length - 1);
    last = (last + overscan).clamp(0, turns.length - 1);
    if (last < first) last = first;
    return TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: offsetBefore(turns, first),
      paddingBottom: totalExtent(turns) - offsetBefore(turns, last + 1),
    );
  }

  /// Shrinks [range] so at most [maxUnmeasured] turns lack a measured height.
  ///
  /// The window stays contiguous. From the focus edge ([preferEnd] → suffix,
  /// else prefix), keep every measured turn and admit unmeasured turns until
  /// [maxUnmeasured]. Avoids dropping already-measured neighbors (scroll churn)
  /// while still capping how many cold rows layout in one frame.
  TurnVisibleRange clampUnmeasuredMounts({
    required List<ThreadTurn> turns,
    required TurnVisibleRange range,
    required int maxUnmeasured,
    required bool preferEnd,
  }) {
    if (turns.isEmpty || range.lastIndex < range.firstIndex) return range;
    final limit = maxUnmeasured < 1 ? 1 : maxUnmeasured;

    var unmeasured = 0;
    for (var i = range.firstIndex; i <= range.lastIndex; i++) {
      if (!isMeasured(turns[i].id)) unmeasured++;
    }
    if (unmeasured <= limit) return range;

    final int first;
    final int last;
    if (preferEnd) {
      last = range.lastIndex;
      var start = last;
      var keptUnmeasured = 0;
      for (var i = range.lastIndex; i >= range.firstIndex; i--) {
        final isUn = !isMeasured(turns[i].id);
        if (isUn) {
          if (keptUnmeasured >= limit) break;
          keptUnmeasured++;
        }
        start = i;
      }
      first = start;
    } else {
      first = range.firstIndex;
      var end = first;
      var keptUnmeasured = 0;
      for (var i = range.firstIndex; i <= range.lastIndex; i++) {
        final isUn = !isMeasured(turns[i].id);
        if (isUn) {
          if (keptUnmeasured >= limit) break;
          keptUnmeasured++;
        }
        end = i;
      }
      last = end;
    }

    return TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: offsetBefore(turns, first),
      paddingBottom: totalExtent(turns) - offsetBefore(turns, last + 1),
    );
  }
}
