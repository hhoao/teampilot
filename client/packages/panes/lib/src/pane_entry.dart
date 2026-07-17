import 'package:flutter/foundation.dart';
import 'package:panes/src/pane_size.dart';

/// Controls how a pane participates in cascade resize operations.
///
/// When a resize operation would push a pane past its constraints,
/// the remaining delta can cascade to neighboring panes based on their behavior.
enum ResizeBehavior {
  /// Absorb resize delta first, before other panes.
  ///
  /// This is the default for fractional panes.
  eager,

  /// Absorb resize delta last, after eager panes are exhausted.
  reluctant,

  /// Never absorb cascade delta; skip entirely.
  ///
  /// This is the default for pixel-sized panes.
  fixed,
}

/// Configuration for a single pane within a [PaneController].
@immutable
class PaneEntry {
  /// Unique identifier for this pane.
  final String id;

  /// Whether the pane is initially visible.
  final bool visible;

  /// The initial size of the pane.
  final PaneSize initialSize;

  /// The minimum size of the pane.
  final PaneSize? minSize;

  /// The maximum size of the pane.
  final PaneSize? maxSize;

  /// Whether the pane should automatically hide when resized below a threshold.
  final bool autoHide;

  /// The threshold for auto-hiding.
  ///
  /// Can be a pixel value or a fraction. If null, defaults to [minSize]
  /// (or 20.0 pixels if minSize is also not set).
  final PaneSize? autoHideThreshold;

  /// How this pane participates in cascade resize operations.
  ///
  /// When null, defaults based on [initialSize] type:
  /// - Pixel panes default to [ResizeBehavior.fixed]
  /// - Fractional panes default to [ResizeBehavior.eager]
  ///
  /// Set explicitly to override the default behavior.
  final ResizeBehavior? resizeBehavior;

  /// Creates a [PaneEntry].
  const PaneEntry({
    required this.id,
    this.visible = true,
    required this.initialSize,
    this.minSize,
    this.maxSize,
    this.autoHide = false,
    this.autoHideThreshold,
    this.resizeBehavior,
  });

  /// Returns the effective resize behavior for this pane.
  ///
  /// If [resizeBehavior] is explicitly set, returns that value.
  /// Otherwise, returns [ResizeBehavior.fixed] for pixel panes
  /// and [ResizeBehavior.eager] for fractional panes.
  ResizeBehavior get effectiveResizeBehavior {
    if (resizeBehavior != null) return resizeBehavior!;
    return initialSize is PaneSizePixel
        ? ResizeBehavior.fixed
        : ResizeBehavior.eager;
  }

  /// Creates a copy of this entry with the given fields replaced with new values.
  PaneEntry copyWith({
    String? id,
    bool? visible,
    PaneSize? initialSize,
    PaneSize? minSize,
    PaneSize? maxSize,
    bool? autoHide,
    PaneSize? autoHideThreshold,
    ResizeBehavior? resizeBehavior,
  }) {
    return PaneEntry(
      id: id ?? this.id,
      visible: visible ?? this.visible,
      initialSize: initialSize ?? this.initialSize,
      minSize: minSize ?? this.minSize,
      maxSize: maxSize ?? this.maxSize,
      autoHide: autoHide ?? this.autoHide,
      autoHideThreshold: autoHideThreshold ?? this.autoHideThreshold,
      resizeBehavior: resizeBehavior ?? this.resizeBehavior,
    );
  }
}
