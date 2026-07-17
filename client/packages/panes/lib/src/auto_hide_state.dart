import 'package:panes/src/pane_entry.dart';
import 'package:panes/src/resize_calculator.dart';

/// Represents the auto-hide state of a single pane.
///
/// This sealed class hierarchy makes all possible states explicit
/// and forces handling of each case.
sealed class AutoHideState {
  const AutoHideState();

  /// The size to use for display purposes.
  double? get visualSize;

  /// The size to use for resize delta calculations.
  /// May differ from visualSize when tracking virtual position.
  double? get calculationSize;
}

/// Pane is visible and at a normal size.
class AutoHideVisible extends AutoHideState {
  /// The current size in pixels (if pixel-sized pane).
  final double? pixelSize;

  const AutoHideVisible({this.pixelSize});

  @override
  double? get visualSize => pixelSize;

  @override
  double? get calculationSize => pixelSize;
}

/// Pane is being dragged below its minimum size.
///
/// The visual size stays at min, but we track the virtual position
/// so that resize deltas accumulate correctly.
class AutoHideDraggingBelowMin extends AutoHideState {
  /// The size displayed (clamped to min).
  final double displaySize;

  /// The virtual position (below min) for delta calculations.
  final double virtualSize;

  const AutoHideDraggingBelowMin({
    required this.displaySize,
    required this.virtualSize,
  });

  @override
  double? get visualSize => displaySize;

  @override
  double? get calculationSize => virtualSize;
}

/// Pane is hidden.
class AutoHideHidden extends AutoHideState {
  /// The size to restore when shown again.
  final double? restoreSize;

  const AutoHideHidden({this.restoreSize});

  @override
  double? get visualSize => null;

  @override
  double? get calculationSize => null;
}

/// Pane is hidden but a drag is in progress that might reveal it.
///
/// We track the virtual drag position to detect when the user
/// drags back by the threshold amount.
class AutoHidePendingReveal extends AutoHideState {
  /// The size to restore when revealed.
  final double restoreSize;

  /// Current virtual position (negative = dragging further closed).
  final double virtualPosition;

  /// Lowest point reached during this drag (for reverse detection).
  final double lowestPoint;

  const AutoHidePendingReveal({
    required this.restoreSize,
    required this.virtualPosition,
    required this.lowestPoint,
  });

  @override
  double? get visualSize => null;

  @override
  double? get calculationSize => virtualPosition;
}

/// Result of processing a resize operation through the auto-hide state machine.
sealed class AutoHideResult {
  const AutoHideResult();
}

/// Size was updated normally.
class AutoHideResultUpdated extends AutoHideResult {
  final AutoHideState newState;
  final double newSize;

  const AutoHideResultUpdated({required this.newState, required this.newSize});
}

/// Pane should be hidden.
class AutoHideResultHide extends AutoHideResult {
  final AutoHideState newState;

  const AutoHideResultHide({required this.newState});
}

/// Pane should be revealed (was hidden, now showing).
class AutoHideResultReveal extends AutoHideResult {
  final AutoHideState newState;

  /// The size to reveal at (may be clamped to minSize).
  final double revealSize;

  /// The original requested size before clamping.
  /// If less than revealSize, indicates undershoot that needs tracking.
  final double requestedSize;

  const AutoHideResultReveal({
    required this.newState,
    required this.revealSize,
    required this.requestedSize,
  });
}

/// No change needed (e.g., still tracking virtual position).
class AutoHideResultNoChange extends AutoHideResult {
  final AutoHideState newState;

  const AutoHideResultNoChange({required this.newState});
}

/// Processes auto-hide behavior as a pure state machine.
///
/// All methods are static and have no side effects.
class AutoHideBehavior {
  AutoHideBehavior._();

  /// Processes a resize operation and returns the result.
  ///
  /// [currentState] is the current auto-hide state for this pane.
  /// [requestedSize] is the size the user is trying to resize to (in pixels).
  /// [entry] is the pane configuration.
  /// [context] provides layout information for constraint calculations.
  /// [isVisible] indicates if the pane is currently visible.
  static AutoHideResult processResize({
    required AutoHideState currentState,
    required double requestedSize,
    required PaneEntry entry,
    required ResizeContext context,
    required bool isVisible,
  }) {
    final minSize = ResizeCalculator.getMinPixels(entry, context);
    final maxSize = ResizeCalculator.getMaxPixels(entry, context);
    final threshold = ResizeCalculator.getAutoHideThreshold(entry, context);

    // Route to appropriate handler based on state
    return switch (currentState) {
      // Hidden pane being dragged to reveal
      AutoHidePendingReveal() => _processPendingReveal(
          currentState,
          requestedSize,
          threshold,
          minSize,
          maxSize,
        ),
      // Visible pane being resized
      _ when isVisible => _processVisibleResize(
          currentState,
          requestedSize,
          entry,
          minSize,
          maxSize,
          threshold,
        ),
      // Pane is hidden and not in pending reveal - no resize action
      _ => AutoHideResultNoChange(newState: currentState),
    };
  }

  static AutoHideResult _processPendingReveal(
    AutoHidePendingReveal state,
    double requestedSize,
    double threshold,
    double minSize,
    double maxSize,
  ) {
    // Track lowest point
    final newLowest =
        requestedSize < state.lowestPoint ? requestedSize : state.lowestPoint;

    // Check if user dragged back by threshold amount
    final reverseDelta = requestedSize - newLowest;
    if (reverseDelta >= threshold) {
      // Reveal the pane
      final revealSize = requestedSize.clamp(minSize, maxSize);
      return AutoHideResultReveal(
        newState: AutoHideVisible(pixelSize: revealSize),
        revealSize: revealSize,
        requestedSize: requestedSize,
      );
    }

    // Still tracking, update virtual position
    return AutoHideResultNoChange(
      newState: AutoHidePendingReveal(
        restoreSize: state.restoreSize,
        virtualPosition: requestedSize,
        lowestPoint: newLowest,
      ),
    );
  }

  static AutoHideResult _processVisibleResize(
    AutoHideState currentState,
    double requestedSize,
    PaneEntry entry,
    double minSize,
    double maxSize,
    double threshold,
  ) {
    // Check if dragging below threshold - should hide
    if (requestedSize < threshold) {
      // Determine restore size
      final restoreSize = switch (currentState) {
        AutoHideVisible(:final pixelSize) =>
          pixelSize ?? entry.initialSize.size,
        AutoHideDraggingBelowMin(:final displaySize) => displaySize,
        _ => entry.initialSize.size,
      };

      return AutoHideResultHide(
        newState: AutoHidePendingReveal(
          restoreSize: restoreSize,
          virtualPosition: requestedSize,
          lowestPoint: requestedSize,
        ),
      );
    }

    // Check if dragging below min but above threshold
    // Display clamps to minSize while we track the virtual position
    if (requestedSize < minSize) {
      return AutoHideResultUpdated(
        newState: AutoHideDraggingBelowMin(
          displaySize: minSize,
          virtualSize: requestedSize,
        ),
        newSize: minSize,
      );
    }

    // Normal resize within constraints
    final clampedSize = requestedSize.clamp(minSize, maxSize);
    return AutoHideResultUpdated(
      newState: AutoHideVisible(pixelSize: clampedSize),
      newSize: clampedSize,
    );
  }

  /// Initializes state for starting a drag operation.
  ///
  /// Call this when resize starts on an auto-hide pane.
  static AutoHideState initializeDragState({
    required bool isVisible,
    required double? currentSize,
    required PaneEntry entry,
  }) {
    if (!isVisible) {
      // Hidden pane - set up for potential drag-to-reveal
      return AutoHidePendingReveal(
        restoreSize: currentSize ?? entry.initialSize.size,
        virtualPosition: 0,
        lowestPoint: 0,
      );
    }

    // Visible pane - just track current size
    return AutoHideVisible(pixelSize: currentSize);
  }

  /// Clears drag state when resize ends.
  ///
  /// Returns the appropriate resting state.
  static AutoHideState finalizeDragState({
    required AutoHideState currentState,
    required bool isVisible,
  }) {
    if (!isVisible) {
      // Pane is hidden - preserve restore size if available
      final restoreSize = switch (currentState) {
        AutoHidePendingReveal(:final restoreSize) => restoreSize,
        AutoHideVisible(:final pixelSize) => pixelSize,
        AutoHideDraggingBelowMin(:final displaySize) => displaySize,
        AutoHideHidden(:final restoreSize) => restoreSize,
      };
      return AutoHideHidden(restoreSize: restoreSize);
    }

    // Pane is visible - convert to simple visible state
    final size = currentState.visualSize;
    return AutoHideVisible(pixelSize: size);
  }
}
