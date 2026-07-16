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

  /// Like [setMeasured] but ignores shrinks (extent flicker while sticking).
  void setMeasuredMonotonic(String turnId, double height) {
    if (height <= 0) return;
    final previous = _measured[turnId];
    if (previous != null && height < previous) return;
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
    final start = scrollPixels.clamp(0.0, double.infinity);
    final end = start + viewportHeight;
    var offset = 0.0;
    var first = 0;
    var last = turns.length - 1;
    var foundFirst = false;
    for (var i = 0; i < turns.length; i++) {
      final h = heightOf(turns[i].id);
      final top = offset;
      final bottom = offset + h;
      if (!foundFirst && bottom > start) {
        first = i;
        foundFirst = true;
      }
      if (top < end) last = i;
      offset = bottom;
    }
    first = (first - overscan).clamp(0, turns.length - 1);
    last = (last + overscan).clamp(0, turns.length - 1);

    var paddingTop = 0.0;
    for (var i = 0; i < first; i++) {
      paddingTop += heightOf(turns[i].id);
    }
    var paddingBottom = 0.0;
    for (var i = last + 1; i < turns.length; i++) {
      paddingBottom += heightOf(turns[i].id);
    }
    return TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
    );
  }
}
