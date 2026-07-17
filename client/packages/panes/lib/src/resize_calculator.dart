import 'package:panes/src/pane_entry.dart';
import 'package:panes/src/pane_size.dart';

/// Context needed for resize calculations.
///
/// This captures the layout state at the time of resize, allowing
/// pure calculations without accessing widget state.
class ResizeContext {
  /// Total size of the container in the resize direction.
  final double containerSize;

  /// Thickness of each resizer.
  final double resizerThickness;

  /// Number of resizers (entries.length - 1).
  final int resizerCount;

  /// Total flex sum of all fractional panes.
  final double totalFlexSum;

  /// Total fixed size of all pixel-sized panes.
  final double totalFixedSize;

  const ResizeContext({
    required this.containerSize,
    required this.resizerThickness,
    required this.resizerCount,
    required this.totalFlexSum,
    required this.totalFixedSize,
  });

  /// The space available for flex panes after subtracting fixed sizes and resizers.
  double get flexSpace =>
      containerSize - totalFixedSize - (resizerThickness * resizerCount);
}

/// Pure functions for resize calculations and constraint enforcement.
///
/// All methods are static and have no side effects, making them
/// easy to test and reason about.
class ResizeCalculator {
  ResizeCalculator._();

  /// Converts a [PaneSize] to pixels given the resize context.
  ///
  /// For pixel sizes, returns the value directly.
  /// For fractional sizes, calculates based on available flex space.
  static double toPixels(PaneSize size, ResizeContext context) {
    return switch (size) {
      PaneSizePixel(:final pixels) => pixels,
      PaneSizeFraction(:final fraction) => context.flexSpace > 0
          ? (fraction / context.totalFlexSum) * context.flexSpace
          : 0,
    };
  }

  /// Converts a pixel value to a fraction given the resize context.
  static double toFraction(double pixels, ResizeContext context) {
    if (context.flexSpace <= 0) return 0;
    return (pixels / context.flexSpace) * context.totalFlexSum;
  }

  /// Gets the minimum size in pixels for a pane entry.
  ///
  /// Returns 0 if no minSize is specified.
  static double getMinPixels(PaneEntry entry, ResizeContext context) {
    final minSize = entry.minSize;
    if (minSize == null) return 0;
    return toPixels(minSize, context);
  }

  /// Gets the maximum size in pixels for a pane entry.
  ///
  /// Returns [double.infinity] if no maxSize is specified.
  static double getMaxPixels(PaneEntry entry, ResizeContext context) {
    final maxSize = entry.maxSize;
    if (maxSize == null) return double.infinity;
    return toPixels(maxSize, context);
  }

  /// Clamps a pixel value to the entry's min/max constraints.
  static double clampPixels(
    double pixels,
    PaneEntry entry,
    ResizeContext context,
  ) {
    final min = getMinPixels(entry, context);
    final max = getMaxPixels(entry, context);
    return pixels.clamp(min, max);
  }

  /// Gets the auto-hide threshold in pixels for a pane entry.
  ///
  /// - If autoHideThreshold is a pixel value, use it directly
  /// - If autoHideThreshold is a fraction, interpret as fraction of minSize
  /// - Otherwise default to half of minSize
  static double getAutoHideThreshold(PaneEntry entry, ResizeContext context) {
    final threshold = entry.autoHideThreshold;
    final minPixels = getMinPixels(entry, context);

    if (threshold != null) {
      return switch (threshold) {
        PaneSizePixel(:final pixels) => pixels,
        // Fraction means "fraction of minSize", not "fraction of flexSpace"
        PaneSizeFraction(:final fraction) => minPixels * fraction,
      };
    }
    // Default: half of minSize (threshold should be BELOW minSize)
    if (minPixels > 0) {
      return minPixels * 0.5;
    }
    // Fallback default
    return 20.0;
  }

  /// Calculates the result of applying a delta to a pixel-sized pane.
  ///
  /// Returns the new size after applying constraints.
  /// Does NOT handle auto-hide logic - that's separate.
  static double applyPixelDelta(
    double currentPixels,
    double delta,
    PaneEntry entry,
    ResizeContext context,
  ) {
    final newSize = currentPixels + delta;
    return clampPixels(newSize, entry, context);
  }

  /// Calculates the result of resizing two adjacent fractional panes.
  ///
  /// When both panes are fractional, resizing one affects the other.
  /// Returns (newFraction1, newFraction2) with constraints applied.
  static (double, double) applyFractionalDelta({
    required double currentFraction1,
    required double currentFraction2,
    required double deltaPixels,
    required PaneEntry entry1,
    required PaneEntry entry2,
    required ResizeContext context,
  }) {
    if (context.flexSpace <= 0) {
      return (currentFraction1, currentFraction2);
    }

    // Convert pixel delta to flex delta
    double deltaFlex = (deltaPixels * context.totalFlexSum) / context.flexSpace;

    // Calculate min constraints in flex units
    double minFlex1 = 0;
    if (entry1.minSize != null) {
      minFlex1 = switch (entry1.minSize!) {
        PaneSizePixel(:final pixels) =>
          (pixels * context.totalFlexSum) / context.flexSpace,
        PaneSizeFraction(:final fraction) => fraction,
      };
    }

    double minFlex2 = 0;
    if (entry2.minSize != null) {
      minFlex2 = switch (entry2.minSize!) {
        PaneSizePixel(:final pixels) =>
          (pixels * context.totalFlexSum) / context.flexSpace,
        PaneSizeFraction(:final fraction) => fraction,
      };
    }

    // Calculate max constraints in flex units
    double maxFlex1 = double.infinity;
    if (entry1.maxSize != null) {
      maxFlex1 = switch (entry1.maxSize!) {
        PaneSizePixel(:final pixels) =>
          (pixels * context.totalFlexSum) / context.flexSpace,
        PaneSizeFraction(:final fraction) => fraction,
      };
    }

    double maxFlex2 = double.infinity;
    if (entry2.maxSize != null) {
      maxFlex2 = switch (entry2.maxSize!) {
        PaneSizePixel(:final pixels) =>
          (pixels * context.totalFlexSum) / context.flexSpace,
        PaneSizeFraction(:final fraction) => fraction,
      };
    }

    // Clamp delta to respect all constraints
    // entry1 grows by deltaFlex, entry2 shrinks by deltaFlex
    double minDelta = minFlex1 - currentFraction1; // entry1 can't go below min
    double maxDelta = maxFlex1 - currentFraction1; // entry1 can't go above max
    double minDelta2 =
        currentFraction2 - maxFlex2; // entry2 shrinking can't push it above max
    double maxDelta2 =
        currentFraction2 - minFlex2; // entry2 can't shrink below min

    // Combine constraints
    double effectiveMinDelta =
        [minDelta, minDelta2].reduce((a, b) => a > b ? a : b);
    double effectiveMaxDelta =
        [maxDelta, maxDelta2].reduce((a, b) => a < b ? a : b);

    deltaFlex = deltaFlex.clamp(effectiveMinDelta, effectiveMaxDelta);

    return (currentFraction1 + deltaFlex, currentFraction2 - deltaFlex);
  }

  /// Calculates how much delta a pane can absorb given its constraints.
  ///
  /// Returns (absorbed, remaining) where:
  /// - absorbed: the portion of delta that was applied to this pane
  /// - remaining: the leftover delta to cascade to the next pane
  ///
  /// A positive delta increases the pane size; negative decreases it.
  static (double absorbed, double remaining) calculateAbsorption({
    required double currentSize,
    required double delta,
    required PaneEntry entry,
    required ResizeContext context,
  }) {
    final minSize = getMinPixels(entry, context);
    final maxSize = getMaxPixels(entry, context);

    final requestedSize = currentSize + delta;
    final clampedSize = requestedSize.clamp(minSize, maxSize);
    final absorbed = clampedSize - currentSize;
    final remaining = delta - absorbed;

    return (absorbed, remaining);
  }

  /// Builds a [ResizeContext] from a list of entries and their current sizes.
  ///
  /// [getCurrentPixelSize] should return the current pixel size override, or null.
  /// [getCurrentFraction] should return the current fraction override, or null.
  static ResizeContext buildContext({
    required List<PaneEntry> entries,
    required double containerSize,
    required double resizerThickness,
    required double? Function(String id) getCurrentPixelSize,
    required double? Function(String id) getCurrentFraction,
  }) {
    double totalFixedSize = 0;
    double totalFlexSum = 0;

    for (final entry in entries) {
      // Check entry type FIRST - fractional panes stay fractional even if
      // auto-hide state was initialized (which incorrectly stores fraction as pixels)
      if (entry.initialSize is PaneSizeFraction) {
        // Flex pane - always use fractional calculation
        final fraction = getCurrentFraction(entry.id);
        totalFlexSum += fraction ?? entry.initialSize.size;
      } else {
        // Pixel pane - check for size override
        final pixelSize = getCurrentPixelSize(entry.id);
        if (pixelSize != null) {
          totalFixedSize += pixelSize;
        } else {
          totalFixedSize += (entry.initialSize as PaneSizePixel).pixels;
        }
      }
    }

    return ResizeContext(
      containerSize: containerSize,
      resizerThickness: resizerThickness,
      resizerCount: entries.length - 1,
      totalFlexSum: totalFlexSum,
      totalFixedSize: totalFixedSize,
    );
  }
}
