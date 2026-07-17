import 'package:flutter/widgets.dart';

/// Handles the state and calculations for a resize drag operation.
///
/// This class tracks the cumulative drag distance from the start position,
/// ensuring consistent behavior even when the resizer position changes
/// (e.g., when snapping back from overshoot).
class ResizeDragHandler {
  /// The starting size of the pane when the drag began.
  final double startSize;

  /// Cumulative drag distance from start (positive = grow, negative = shrink).
  double _cumulativeDelta = 0;

  /// Creates a handler for a resize drag starting at [startSize].
  ResizeDragHandler({required this.startSize});

  /// The current cumulative delta from the drag start.
  double get cumulativeDelta => _cumulativeDelta;

  /// The requested size based on start size + cumulative delta.
  double get requestedSize => startSize + _cumulativeDelta;

  /// Adds a delta to the cumulative drag distance.
  ///
  /// Returns the new requested size.
  double addDelta(double delta) {
    _cumulativeDelta += delta;
    return requestedSize;
  }

  /// Resets the cumulative delta to zero.
  void reset() {
    _cumulativeDelta = 0;
  }
}

/// Tracks global mouse position for accurate delta calculation.
///
/// This prevents drift when the dragged widget's position changes
/// during the drag (e.g., when a pane snaps back from overshoot).
class GlobalDragTracker {
  Offset? _lastGlobalPosition;
  Offset? _startGlobalPosition;

  /// Call when drag starts.
  void onDragStart(Offset globalPosition) {
    _startGlobalPosition = globalPosition;
    _lastGlobalPosition = globalPosition;
  }

  /// Call when drag ends.
  void onDragEnd() {
    _startGlobalPosition = null;
    _lastGlobalPosition = null;
  }

  /// Calculates the delta from the last position.
  ///
  /// Returns the delta for the specified [direction].
  double calculateDelta(Offset currentGlobalPosition, Axis direction) {
    final lastGlobal = _lastGlobalPosition ?? currentGlobalPosition;

    final delta = direction == Axis.horizontal
        ? currentGlobalPosition.dx - lastGlobal.dx
        : currentGlobalPosition.dy - lastGlobal.dy;

    _lastGlobalPosition = currentGlobalPosition;
    return delta;
  }

  /// Calculates the total delta from the start position.
  ///
  /// This is more accurate for cumulative tracking as it doesn't
  /// accumulate floating point errors from many small deltas.
  double calculateTotalDelta(Offset currentGlobalPosition, Axis direction) {
    final startGlobal = _startGlobalPosition ?? currentGlobalPosition;

    return direction == Axis.horizontal
        ? currentGlobalPosition.dx - startGlobal.dx
        : currentGlobalPosition.dy - startGlobal.dy;
  }

  /// Whether a drag is currently in progress.
  bool get isDragging => _startGlobalPosition != null;
}
