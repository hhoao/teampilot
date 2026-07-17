import 'package:flutter/foundation.dart';
import 'package:panes/src/auto_hide_state.dart';
import 'package:panes/src/pane_entry.dart';
import 'package:panes/src/pane_size.dart';
import 'package:panes/src/resize_calculator.dart';

/// Manages the state (size, visibility, maximization) of panes.
class PaneController extends ChangeNotifier {
  final List<PaneEntry> _entries;

  /// Core size storage.
  final Map<String, double> _pixelSizes = {};
  final Map<String, double> _fractionalSizes = {};
  final Map<String, bool> _visibilityOverrides = {};

  /// Auto-hide state per pane (replaces scattered maps).
  final Map<String, AutoHideState> _autoHideStates = {};

  /// Tracks virtual position when dragging past bounds.
  /// Used to implement "dead zone" behavior where reversing doesn't resize
  /// until the virtual position comes back within bounds.
  final Map<String, double> _maxOvershootPositions = {};
  final Map<String, double> _minUndershootPositions = {};

  /// Whether a resize drag is currently in progress.
  bool _isResizing = false;

  /// Creates a [PaneController] with the given list of [entries].
  PaneController({required List<PaneEntry> entries})
      : _entries = List.from(entries);

  /// The list of pane entries managed by this controller.
  List<PaneEntry> get entries => List.unmodifiable(_entries);

  /// Whether a resize drag is currently in progress.
  bool get isResizing => _isResizing;

  // ---------------------------------------------------------------------------
  // Dynamic Pane Management
  // ---------------------------------------------------------------------------

  /// Adds a new pane to the controller.
  ///
  /// Throws an [ArgumentError] if a pane with the same ID already exists.
  /// If [index] is provided, the pane is inserted at that position.
  /// Otherwise, it is added to the end.
  void addPane(PaneEntry entry, {int? index}) {
    if (_entries.any((e) => e.id == entry.id)) {
      throw ArgumentError('Pane with ID ${entry.id} already exists');
    }

    if (index != null) {
      final safeIndex = index.clamp(0, _entries.length);
      _entries.insert(safeIndex, entry);
    } else {
      _entries.add(entry);
    }

    notifyListeners();
  }

  /// Adds multiple panes to the controller in a single operation.
  void addPanes(Iterable<PaneEntry> entries) {
    for (final entry in entries) {
      if (_entries.any((e) => e.id == entry.id)) {
        throw ArgumentError('Pane with ID ${entry.id} already exists');
      }
      _entries.add(entry);
    }
    notifyListeners();
  }

  /// Removes the pane with the given [id] and cleans up its state.
  void removePane(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return;

    _entries.removeAt(index);
    _cleanupState(id);

    if (_maximizedPaneId == id) {
      _maximizedPaneId = null;
    }

    notifyListeners();
  }

  /// Updates an existing pane's configuration.
  ///
  /// The pane is identified by [entry.id].
  void updatePane(PaneEntry entry) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index == -1) {
      throw ArgumentError('Pane with ID ${entry.id} not found');
    }

    final oldEntry = _entries[index];
    _entries[index] = entry;

    // If the size type changed (pixel vs fraction), clear overrides to
    // ensure the new initialSize type takes effect.
    if (oldEntry.initialSize.runtimeType != entry.initialSize.runtimeType) {
      _pixelSizes.remove(entry.id);
      _fractionalSizes.remove(entry.id);
      _autoHideStates.remove(entry.id);
    }

    notifyListeners();
  }

  void _cleanupState(String id) {
    _pixelSizes.remove(id);
    _fractionalSizes.remove(id);
    _visibilityOverrides.remove(id);
    _autoHideStates.remove(id);
    _maxOvershootPositions.remove(id);
    _minUndershootPositions.remove(id);
  }

  // ---------------------------------------------------------------------------
  // Visibility
  // ---------------------------------------------------------------------------

  /// Returns true if the pane with the given [id] is effectively visible.
  bool isVisible(String id) {
    return _visibilityOverrides[id] ??
        _entries
            .firstWhere(
              (e) => e.id == id,
              orElse: () => throw Exception('Pane $id not found'),
            )
            .visible;
  }

  /// Hides the pane with the given [id].
  void hide(String id) {
    if (_visibilityOverrides[id] == false) return;
    _visibilityOverrides[id] = false;
    notifyListeners();
  }

  /// Shows the pane with the given [id].
  ///
  /// If the pane was auto-hidden, restores it to its pre-hide size.
  void show(String id) {
    if (_visibilityOverrides[id] == true) return;
    _visibilityOverrides[id] = true;

    // Restore size from auto-hide state if available
    if (_autoHideStates[id]
        case AutoHideHidden(:final restoreSize?) ||
            AutoHidePendingReveal(:final restoreSize)) {
      _pixelSizes[id] = restoreSize;
      _autoHideStates[id] = AutoHideVisible(pixelSize: restoreSize);
    }

    notifyListeners();
  }

  /// Toggles the visibility of the pane with the given [id].
  void toggle(String id) {
    if (isVisible(id)) {
      hide(id);
    } else {
      show(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Resize Operations
  // ---------------------------------------------------------------------------

  /// Called when a resize drag starts.
  ///
  /// Initializes tracking state for auto-hide panes.
  void beginResize(String paneId, {String? adjacentPaneId}) {
    _isResizing = true;

    _initializeResizeState(paneId);
    if (adjacentPaneId != null) {
      _initializeResizeState(adjacentPaneId);
    }

    notifyListeners();
  }

  void _initializeResizeState(String id) {
    final entry = _entries.cast<PaneEntry?>().firstWhere(
          (e) => e?.id == id,
          orElse: () => null,
        );
    if (entry == null || !entry.autoHide) return;

    final currentSize = _pixelSizes[id] ?? entry.initialSize.size;
    _autoHideStates[id] = AutoHideBehavior.initializeDragState(
      isVisible: isVisible(id),
      currentSize: currentSize,
      entry: entry,
    );
  }

  /// Called when a resize drag ends.
  ///
  /// Cleans up tracking state.
  void endResize(String paneId, {String? adjacentPaneId}) {
    _isResizing = false;

    _finalizeResizeState(paneId);
    if (adjacentPaneId != null) {
      _finalizeResizeState(adjacentPaneId);
    }

    notifyListeners();
  }

  void _finalizeResizeState(String id) {
    // Clear bound tracking
    _maxOvershootPositions.remove(id);
    _minUndershootPositions.remove(id);

    // Finalize auto-hide state if present
    final state = _autoHideStates[id];
    if (state == null) return;

    // Check if pane still exists before finalizing behavior
    final entryExists = _entries.any((e) => e.id == id);
    if (!entryExists) {
      _autoHideStates.remove(id);
      return;
    }

    _autoHideStates[id] = AutoHideBehavior.finalizeDragState(
      currentState: state,
      isVisible: isVisible(id),
    );
  }

  /// Main entry point for resize operations.
  ///
  /// Handles pixel panes, fractional panes, and auto-hide behavior.
  /// All constraint enforcement happens here.
  ///
  /// [resizerIndex] is optional and used for cascade resize operations.
  /// If not provided, it will be calculated from [paneId] (resizer is after the pane).
  void resize({
    required String paneId,
    required double delta,
    required double containerSize,
    required double resizerThickness,
    String? adjacentPaneId,
    int? resizerIndex,
  }) {
    if (delta == 0) return;

    final entry = _getEntry(paneId);
    final context = ResizeCalculator.buildContext(
      entries: _entries,
      containerSize: containerSize,
      resizerThickness: resizerThickness,
      getCurrentPixelSize: _getPixelSizeForCalculation,
      getCurrentFraction: (id) => _fractionalSizes[id],
    );

    // Calculate resizer index if not provided
    // The resizer is positioned after the pane with paneId
    final effectiveResizerIndex =
        resizerIndex ?? _entries.indexWhere((e) => e.id == paneId);

    // Determine if this is a pixel or fractional resize
    final isPixelPane =
        _pixelSizes[paneId] != null || entry.initialSize is PaneSizePixel;

    if (isPixelPane) {
      _resizePixelPane(
        paneId,
        entry,
        delta,
        context,
        resizerIndex: effectiveResizerIndex,
      );
    } else if (adjacentPaneId != null) {
      // Check if adjacent pane is pixel-sized
      final adjacentEntry = _getEntry(adjacentPaneId);
      final isAdjacentPixel = _pixelSizes[adjacentPaneId] != null ||
          adjacentEntry.initialSize is PaneSizePixel;

      if (isAdjacentPixel) {
        // When resizing a fractional pane adjacent to a pixel pane,
        // we need to respect the fractional pane's min/max constraints.
        // The fractional pane grows/shrinks opposite to the pixel pane.
        final fractionalCurrentSize = _getPixelSizeForCalculation(paneId) ??
            ResizeCalculator.toPixels(entry.initialSize, context);
        final fractionalNewSize = fractionalCurrentSize + delta;

        final minSize = ResizeCalculator.getMinPixels(entry, context);
        final maxSize = ResizeCalculator.getMaxPixels(entry, context);
        final clampedFractionalSize = fractionalNewSize.clamp(minSize, maxSize);
        final clampedDelta = clampedFractionalSize - fractionalCurrentSize;

        // Resize the adjacent pixel pane with the clamped negative delta
        // Note: adjacent pane is AFTER the resizer, so cascade direction is flipped
        _resizePixelPane(
          adjacentPaneId,
          adjacentEntry,
          -clampedDelta,
          context,
          resizerIndex: effectiveResizerIndex,
          isAfterResizer: true,
        );
      } else {
        // Both are fractional
        _resizeFractionalPanes(
          paneId,
          entry,
          adjacentPaneId,
          adjacentEntry,
          delta,
          context,
        );
      }
    }

    notifyListeners();
  }

  void _resizePixelPane(
    String id,
    PaneEntry entry,
    double delta,
    ResizeContext context, {
    int? resizerIndex,
    bool isAfterResizer = false,
  }) {
    // Use virtual position if we're in overshoot/undershoot, otherwise actual size
    final currentSize = _maxOvershootPositions[id] ??
        _minUndershootPositions[id] ??
        _getPixelSizeForCalculation(id) ??
        entry.initialSize.size;
    final requestedSize = currentSize + delta;

    final minSize = ResizeCalculator.getMinPixels(entry, context);
    final maxSize = ResizeCalculator.getMaxPixels(entry, context);

    // Handle max overshoot - track virtual position, clamp display to max
    if (requestedSize > maxSize) {
      final overflow = requestedSize - maxSize;

      // Set the new size FIRST, then rebuild context for cascade
      _maxOvershootPositions[id] = requestedSize;
      _minUndershootPositions.remove(id);
      _pixelSizes[id] = maxSize;
      if (entry.autoHide) {
        _autoHideStates[id] = AutoHideVisible(pixelSize: maxSize);
      }

      // Try to cascade the overflow to other panes with UPDATED context
      // NOTE: Fixed panes do NOT cascade - they just stop at their constraints
      if (resizerIndex != null &&
          entry.effectiveResizeBehavior != ResizeBehavior.fixed) {
        final updatedContext = ResizeCalculator.buildContext(
          entries: _entries,
          containerSize: context.containerSize,
          resizerThickness: context.resizerThickness,
          getCurrentPixelSize: _getPixelSizeForCalculation,
          getCurrentFraction: (id) => _fractionalSizes[id],
        );
        _cascadeResize(
          resizerIndex: resizerIndex,
          delta: overflow,
          context: updatedContext,
          // When pane is AFTER resizer, flip cascade direction
          // (overflow needs to go to panes BEFORE resizer, not after)
          flipDirection: isAfterResizer,
        );
      }

      return;
    }

    // Handle min undershoot for non-auto-hide panes
    // (auto-hide panes have their own below-min tracking)
    //
    // NOTE: We do NOT cascade on undershoot. When a pane hits its min,
    // the resize stops. The "virtual" space below min doesn't actually
    // exist, so there's nothing to distribute to other panes.
    if (!entry.autoHide && requestedSize < minSize) {
      _minUndershootPositions[id] = requestedSize;
      _maxOvershootPositions.remove(id);
      _pixelSizes[id] = minSize;
      return;
    }

    // Within bounds - clear tracking and proceed
    _maxOvershootPositions.remove(id);
    _minUndershootPositions.remove(id);

    if (entry.autoHide) {
      _handleAutoHideResize(id, entry, requestedSize, context);
    } else {
      _handleConstrainedResize(id, entry, requestedSize, context);
    }
  }

  void _handleConstrainedResize(
    String id,
    PaneEntry entry,
    double requestedSize,
    ResizeContext context,
  ) {
    final minSize = ResizeCalculator.getMinPixels(entry, context);
    final maxSize = ResizeCalculator.getMaxPixels(entry, context);
    final clampedSize = requestedSize.clamp(minSize, maxSize);
    _pixelSizes[id] = clampedSize;
  }

  void _handleAutoHideResize(
    String id,
    PaneEntry entry,
    double requestedSize,
    ResizeContext context,
  ) {
    final currentState = _autoHideStates[id] ?? const AutoHideVisible();

    final result = AutoHideBehavior.processResize(
      currentState: currentState,
      requestedSize: requestedSize,
      entry: entry,
      context: context,
      isVisible: isVisible(id),
    );

    switch (result) {
      case AutoHideResultUpdated(:final newState, :final newSize):
        _autoHideStates[id] = newState;
        _pixelSizes[id] = newSize;

      case AutoHideResultHide(:final newState):
        _autoHideStates[id] = newState;
        _visibilityOverrides[id] = false;

      case AutoHideResultReveal(
          :final newState,
          :final revealSize,
          :final requestedSize
        ):
        _autoHideStates[id] = newState;
        _visibilityOverrides[id] = true;
        _pixelSizes[id] = revealSize;

        // If reveal was clamped to minSize, track undershoot so the divider
        // stays aligned with the mouse until virtual position catches up
        if (requestedSize < revealSize) {
          _minUndershootPositions[id] = requestedSize;
        }

      case AutoHideResultNoChange(:final newState):
        _autoHideStates[id] = newState;
    }
  }

  void _resizeFractionalPanes(
    String id1,
    PaneEntry entry1,
    String id2,
    PaneEntry entry2,
    double deltaPixels,
    ResizeContext context,
  ) {
    final currentFrac1 = _fractionalSizes[id1] ?? entry1.initialSize.size;
    final currentFrac2 = _fractionalSizes[id2] ?? entry2.initialSize.size;

    final (newFrac1, newFrac2) = ResizeCalculator.applyFractionalDelta(
      currentFraction1: currentFrac1,
      currentFraction2: currentFrac2,
      deltaPixels: deltaPixels,
      entry1: entry1,
      entry2: entry2,
      context: context,
    );

    _fractionalSizes[id1] = newFrac1;
    _fractionalSizes[id2] = newFrac2;
  }

  // ---------------------------------------------------------------------------
  // Cascade Resize
  // ---------------------------------------------------------------------------

  /// Collects panes for cascade resize in the given direction.
  ///
  /// [resizerIndex] is the index of the resizer being dragged (0-based).
  /// [forward] determines direction: true = higher indices, false = lower indices.
  ///
  /// Returns entries sorted by resize behavior priority:
  /// 1. Eager panes first (absorb delta first)
  /// 2. Reluctant panes last (absorb delta after eager exhausted)
  /// 3. Fixed panes are excluded entirely
  ///
  /// IMPORTANT: Collection stops when encountering a fractional pane.
  /// Fractional panes naturally handle redistribution through the flex layout,
  /// so we don't cascade "through" them to reach panes on the other side.
  List<PaneEntry> _collectCascadeTargets({
    required int resizerIndex,
    required bool forward,
  }) {
    final List<PaneEntry> targets = [];

    if (forward) {
      // Collect panes from resizer+1 to end
      for (int i = resizerIndex + 1; i < _entries.length; i++) {
        final entry = _entries[i];
        // Stop at fractional panes - they handle redistribution naturally
        final isPixelPane =
            _pixelSizes[entry.id] != null || entry.initialSize is PaneSizePixel;
        if (!isPixelPane) break;

        if (entry.effectiveResizeBehavior != ResizeBehavior.fixed) {
          targets.add(entry);
        }
      }
    } else {
      // Collect panes from resizer down to 0 (in reverse order)
      for (int i = resizerIndex; i >= 0; i--) {
        final entry = _entries[i];
        // Stop at fractional panes - they handle redistribution naturally
        final isPixelPane =
            _pixelSizes[entry.id] != null || entry.initialSize is PaneSizePixel;
        if (!isPixelPane) break;

        if (entry.effectiveResizeBehavior != ResizeBehavior.fixed) {
          targets.add(entry);
        }
      }
    }

    // Sort by behavior: eager first, then reluctant
    targets.sort((a, b) {
      final aBehavior = a.effectiveResizeBehavior;
      final bBehavior = b.effectiveResizeBehavior;
      if (aBehavior == ResizeBehavior.eager &&
          bBehavior == ResizeBehavior.reluctant) {
        return -1;
      }
      if (aBehavior == ResizeBehavior.reluctant &&
          bBehavior == ResizeBehavior.eager) {
        return 1;
      }
      return 0;
    });

    return targets;
  }

  /// Cascades resize delta through multiple panes.
  ///
  /// When a pane hits its constraint, remaining delta flows to the next pane.
  /// Panes are processed in priority order (eager before reluctant).
  ///
  /// [resizerIndex] is the index of the resizer being dragged.
  /// [delta] is positive when increasing size in the forward direction.
  /// [flipDirection] reverses the cascade direction (used when resizing pane
  /// after the resizer instead of before).
  double _cascadeResize({
    required int resizerIndex,
    required double delta,
    required ResizeContext context,
    bool flipDirection = false,
  }) {
    if (delta == 0) return 0;

    // Determine direction based on delta sign
    // Positive delta = panes before resizer grow, panes after shrink
    // For cascade: we cascade to panes that need to absorb the opposite effect
    //
    // When flipDirection is true (resizing pane AFTER resizer):
    // - Positive delta (growing) needs to take space from panes BEFORE resizer
    // - So we flip: forward becomes !forward
    var forward = delta > 0;
    if (flipDirection) forward = !forward;

    // The "absorbing" panes are those that shrink to allow growth
    final targets = _collectCascadeTargets(
      resizerIndex: resizerIndex,
      forward: forward,
    );

    if (targets.isEmpty) return delta;

    var remainingDelta = delta.abs();

    // Only cascade to pixel panes - fractional panes handle redistribution
    // automatically through the flex layout system
    final pixelTargets = targets
        .where(
            (e) => _pixelSizes[e.id] != null || e.initialSize is PaneSizePixel)
        .toList();

    // Try to absorb with pixel panes (one at a time)
    for (final entry in pixelTargets) {
      if (remainingDelta <= 0) break;

      final currentSize =
          _getPixelSizeForCalculation(entry.id) ?? entry.initialSize.size;

      final (absorbed, remaining) = ResizeCalculator.calculateAbsorption(
        currentSize: currentSize,
        delta: -remainingDelta,
        entry: entry,
        context: context,
      );

      if (absorbed.abs() > 0) {
        // Clear any previous tracking state because the pane is being pushed
        // by its neighbor, meaning its virtual dimensions are no longer valid.
        _maxOvershootPositions.remove(entry.id);
        _minUndershootPositions.remove(entry.id);

        // Properly resize the pane, which correctly triggers auto-hide if needed
        _resizePixelPane(
          entry.id,
          entry,
          absorbed,
          context,
        );
      }

      remainingDelta = remaining.abs();
    }

    // Return consumed delta (original minus remaining, with original sign)
    final consumed = delta.abs() - remainingDelta;
    return delta > 0 ? consumed : -consumed;
  }

  // ---------------------------------------------------------------------------
  // Size Queries
  // ---------------------------------------------------------------------------

  /// Gets the pixel size for resize calculations.
  ///
  /// For auto-hide panes being dragged, returns the virtual position.
  double? _getPixelSizeForCalculation(String id) {
    final state = _autoHideStates[id];
    if (state != null) {
      return state.calculationSize ?? _pixelSizes[id];
    }
    return _pixelSizes[id];
  }

  /// Gets the current pixel size override for the pane [id], if any.
  ///
  /// When auto-hide is tracking a drag below minSize, returns the pending
  /// (intended) size so that resize calculations accumulate correctly.
  double? getPixelSize(String id) {
    return _getPixelSizeForCalculation(id);
  }

  /// Gets the visual pixel size for display purposes.
  ///
  /// Unlike [getPixelSize], this always returns the clamped display size,
  /// ignoring any pending auto-hide tracking.
  double? getVisualPixelSize(String id) => _pixelSizes[id];

  /// Gets the current fractional size override for the pane [id], if any.
  double? getFractionalSize(String id) => _fractionalSizes[id];

  // ---------------------------------------------------------------------------
  // Maximize / Restore
  // ---------------------------------------------------------------------------

  String? _maximizedPaneId;

  /// The ID of the currently maximized pane, if any.
  String? get maximizedPaneId => _maximizedPaneId;

  /// Returns true if any pane is currently maximized.
  bool get isMaximized => _maximizedPaneId != null;

  /// Maximizes the pane with the given [id].
  void maximize(String id) {
    if (_entries.any((e) => e.id == id)) {
      _maximizedPaneId = id;
      notifyListeners();
    }
  }

  /// Restores the maximized pane to its previous state.
  void restore() {
    if (_maximizedPaneId != null) {
      _maximizedPaneId = null;
      notifyListeners();
    }
  }

  /// Toggles between maximized and restored state for the pane with the given [id].
  void toggleMaximize(String id) {
    if (_maximizedPaneId == id) {
      restore();
    } else {
      maximize(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  /// Resets the size of the pane with the given [id] to its initial configuration.
  void resetSize(String id) {
    _pixelSizes.remove(id);
    _fractionalSizes.remove(id);
    _autoHideStates.remove(id);
    _maxOvershootPositions.remove(id);
    _minUndershootPositions.remove(id);
    notifyListeners();
  }

  /// Resets all pane sizes to their initial configurations.
  void resetAll() {
    _pixelSizes.clear();
    _fractionalSizes.clear();
    _autoHideStates.clear();
    _maxOvershootPositions.clear();
    _minUndershootPositions.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Legacy API (for backward compatibility during migration)
  // ---------------------------------------------------------------------------

  /// @Deprecated: Use [resize] instead.
  void updateSize(String id, PaneSize newSize) {
    switch (newSize) {
      case PaneSizePixel(:final pixels):
        var size = pixels;
        if (size < 0) size = 0;
        _pixelSizes[id] = size;

      case PaneSizeFraction(:final fraction):
        var frac = fraction;
        if (frac.isNaN || frac.isInfinite) return;
        if (frac < 0) frac = 0;
        _fractionalSizes[id] = frac;
    }
    notifyListeners();
  }

  /// @Deprecated: Use [beginResize] instead.
  void savePreDragSize(String id) {
    _initializeResizeState(id);
  }

  /// @Deprecated: Use [endResize] instead.
  void clearPreDragSize(String id) {
    _finalizeResizeState(id);
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Saves the current controller state (sizes and visibility) to a map.
  Map<String, dynamic> save() {
    return {
      'pixelSizes': Map<String, double>.from(_pixelSizes),
      'fractionalSizes': Map<String, double>.from(_fractionalSizes),
      'overrides': Map<String, bool>.from(_visibilityOverrides),
    };
  }

  /// Loads the controller state from a map.
  void load(Map<String, dynamic> data) {
    // Clear all state
    _autoHideStates.clear();

    if (data.containsKey('pixelSizes')) {
      final map = data['pixelSizes'] as Map;
      _pixelSizes.clear();
      map.forEach((k, v) {
        if (v is num) _pixelSizes[k.toString()] = v.toDouble();
      });
    }
    if (data.containsKey('fractionalSizes')) {
      final map = data['fractionalSizes'] as Map;
      _fractionalSizes.clear();
      map.forEach((k, v) {
        if (v is num) _fractionalSizes[k.toString()] = v.toDouble();
      });
    }
    if (data.containsKey('overrides')) {
      final map = data['overrides'] as Map;
      _visibilityOverrides.clear();
      map.forEach((k, v) {
        if (v is bool) _visibilityOverrides[k.toString()] = v;
      });
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  PaneEntry _getEntry(String id) {
    return _entries.firstWhere(
      (e) => e.id == id,
      orElse: () => throw Exception('Pane $id not found'),
    );
  }
}
