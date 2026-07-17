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
}
