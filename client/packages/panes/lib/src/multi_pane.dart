import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:panes/src/pane_controller.dart';
import 'package:panes/src/pane_size.dart';
import 'package:panes/src/pane_size_reporter.dart';
import 'package:panes/src/pane_theme.dart';
import 'package:panes/src/resizer.dart';

/// Builder function for creating the widget content of a pane.
typedef PaneBuilder = Widget Function(
  BuildContext context,
  String paneId,
  double animationProgress,
);

/// A widget that displays multiple resizable panes in a row or column.
///
/// It listens to a [PaneController] for changes in pane sizes and visibility.
class MultiPane extends StatefulWidget {
  /// The direction of the layout (horizontal or vertical).
  final Axis direction;

  /// The controller that manages the state of the panes.
  final PaneController controller;

  /// The builder used to create the widget for each pane.
  final PaneBuilder paneBuilder;

  /// The duration of the animation when panes are resized or toggled.
  final Duration animationDuration;

  /// The curve of the animation when panes are resized or toggled.
  final Curve animationCurve;

  /// Creates a [MultiPane].
  const MultiPane({
    super.key,
    required this.direction,
    required this.controller,
    required this.paneBuilder,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeInOut,
  });

  @override
  State<MultiPane> createState() => _MultiPaneState();
}

class _MultiPaneState extends State<MultiPane> {
  /// Bumped when content must drop cached pane widgets.
  int _contentEpoch = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(MultiPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
      _contentEpoch++;
    }
    if (oldWidget.paneBuilder != widget.paneBuilder) {
      _contentEpoch++;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    setState(() {});
  }

  Size _containerSize = Size.zero;

  Widget _paneContent(
    BuildContext context,
    String paneId,
    double animationProgress,
  ) {
    return _StablePaneContent(
      key: ValueKey<String>('stable-$paneId-$_contentEpoch'),
      paneId: paneId,
      animationProgress: animationProgress,
      paneBuilder: widget.paneBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Record size for resize math without LayoutBuilder — nesting
    // LayoutBuilder under the IDE shell forced pane BUILD during layout.
    return PaneSizeReporter(
      onSize: (size) => _containerSize = size,
      child: _buildPanes(context),
    );
  }

  Widget _buildPanes(BuildContext context) {
    // Iterate ALL entries to enable animation even for hidden ones
    final entries = widget.controller.entries;

    // Check for Maximized Pane
    // Maximize swaps the Flex tree for a single expand child, so a new
    // [_StablePaneContent] State mounts and re-invokes paneBuilder (intended).
    if (widget.controller.maximizedPaneId case final maxId?) {
      return SizedBox.expand(
        child: _paneContent(context, maxId, 1.0),
      );
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];

    // Get resizer thicknesses from theme
    final theme = PaneTheme.of(context);
    final resizerHitTestSize = theme.resizerHitTestThickness;
    final resizerLayoutSize = theme.resizerThickness;

    // Use controller's isResizing state
    final isResizing = widget.controller.isResizing;

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isVisible = widget.controller.isVisible(entry.id);

      // Determine effective size (visual)
      double? pixelSize = widget.controller.getVisualPixelSize(entry.id);
      double? fractionalSize = widget.controller.getFractionalSize(
        entry.id,
      );

      PaneSize effectiveSize;
      if (pixelSize != null) {
        effectiveSize = PaneSize.pixel(pixelSize);
      } else if (fractionalSize != null) {
        effectiveSize = PaneSize.fraction(fractionalSize);
      } else {
        effectiveSize = entry.initialSize;
      }

      Widget wrappedChild = switch (effectiveSize) {
        PaneSizePixel(:final pixels) => TweenAnimationBuilder<double>(
            // Stable per pane — including isVisible/pixels in the key remounts
            // the tween at its end value and kills show/hide animation.
            key: ValueKey<String>('pane-${entry.id}'),
            tween: Tween<double>(end: isVisible ? pixels : 0.0),
            duration: isResizing ? Duration.zero : widget.animationDuration,
            curve: widget.animationCurve,
            child: _paneContent(
              context,
              entry.id,
              isVisible ? 1.0 : 0.0,
            ),
            builder: (context, currentSize, child) {
              return SizedBox(
                key: ValueKey<String>('pane-slot-${entry.id}'),
                width: widget.direction == Axis.horizontal
                    ? currentSize
                    : null,
                height:
                    widget.direction == Axis.vertical ? currentSize : null,
                child: SingleChildScrollView(
                  scrollDirection: widget.direction,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width:
                        widget.direction == Axis.horizontal ? pixels : null,
                    height:
                        widget.direction == Axis.vertical ? pixels : null,
                    child: child,
                  ),
                ),
              );
            },
          ),
        PaneSizeFraction(:final fraction) => isVisible
            ? Expanded(
                flex:
                    ((fraction.isNaN || fraction.isInfinite || fraction < 0
                                ? 0
                                : fraction) *
                            100)
                        .toInt(),
                child: _paneContent(context, entry.id, 1.0),
              )
            : const SizedBox.shrink(),
      };

      children.add(wrappedChild);

      // Add resizer if not last
      if (i < entries.length - 1) {
        final nextEntry = entries[i + 1];
        final nextVisible = widget.controller.isVisible(nextEntry.id);

        // Resizer is visible if:
        // 1. Both adjacent panes are visible, OR
        // 2. We're actively resizing (to support drag-to-reveal), OR
        // 3. One pane is hidden with autoHide (edge drag to reveal)
        final bool edgeDragReveal = (entry.autoHide && !isVisible) ||
            (nextEntry.autoHide && !nextVisible);

        bool resizerVisible =
            (isVisible && nextVisible) || isResizing || edgeDragReveal;

        children.add(
          TweenAnimationBuilder<double>(
            duration: isResizing ? Duration.zero : widget.animationDuration,
            curve: widget.animationCurve,
            tween:
                Tween<double>(end: resizerVisible ? resizerLayoutSize : 0),
            builder: (context, currentLayoutSize, child) {
              return ResizerWrapper(
                direction: widget.direction,
                layoutSize: currentLayoutSize,
                hitTestSize: resizerHitTestSize,
                child: Resizer(
                  direction: widget.direction,
                  onResize: (delta) {
                    _handleResize(
                      entry.id,
                      nextEntry.id,
                      delta,
                      resizerLayoutSize, // Pass target size for calculating space
                    );
                  },
                  onResizeStart: () {
                    widget.controller.beginResize(
                      entry.id,
                      adjacentPaneId: nextEntry.id,
                    );
                  },
                  onResizeEnd: () {
                    widget.controller.endResize(
                      entry.id,
                      adjacentPaneId: nextEntry.id,
                    );
                  },
                  onDoubleTap: () {
                    widget.controller.resetSize(entry.id);
                    widget.controller.resetSize(nextEntry.id);
                  },
                ),
              );
            },
          ),
        );
      }
    }

    return Flex(
      direction: widget.direction,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _handleResize(
    String paneId,
    String adjacentPaneId,
    double delta,
    double resizerLayoutSize,
  ) {
    final containerSize = widget.direction == Axis.horizontal
        ? _containerSize.width
        : _containerSize.height;

    widget.controller.resize(
      paneId: paneId,
      delta: delta,
      containerSize: containerSize,
      resizerThickness: resizerLayoutSize,
      adjacentPaneId: adjacentPaneId,
    );
  }
}

/// Caches [paneBuilder] output so size-only [MultiPane] rebuilds do not
/// reconstruct pane content (resize / animation ticks).
class _StablePaneContent extends StatefulWidget {
  const _StablePaneContent({
    super.key,
    required this.paneId,
    required this.animationProgress,
    required this.paneBuilder,
  });

  final String paneId;
  final double animationProgress;
  final PaneBuilder paneBuilder;

  @override
  State<_StablePaneContent> createState() => _StablePaneContentState();
}

class _StablePaneContentState extends State<_StablePaneContent> {
  Widget? _child;

  @override
  void didUpdateWidget(covariant _StablePaneContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paneId != widget.paneId ||
        oldWidget.animationProgress != widget.animationProgress ||
        oldWidget.paneBuilder != widget.paneBuilder) {
      _child = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _child ??= widget.paneBuilder(
      context,
      widget.paneId,
      widget.animationProgress,
    );
  }
}

/// A wrapper around a child that sizes itself to `layoutSize` in the layout axis
/// but allows the child to layout at `hitTestSize` and properly redirects
/// hit tests beyond the `layoutSize` bounds.
class ResizerWrapper extends SingleChildRenderObjectWidget {
  final Axis direction;
  final double layoutSize;
  final double hitTestSize;

  const ResizerWrapper({
    super.key,
    required this.direction,
    required this.layoutSize,
    required this.hitTestSize,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderResizerWrapper(
        direction: direction,
        layoutSize: layoutSize,
        hitTestSize: hitTestSize,
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderResizerWrapper renderObject) {
    renderObject
      ..direction = direction
      ..layoutSize = layoutSize
      ..hitTestSize = hitTestSize;
  }
}

class _RenderResizerWrapper extends RenderProxyBox {
  _RenderResizerWrapper({
    required Axis direction,
    required double layoutSize,
    required double hitTestSize,
  })  : _direction = direction,
        _layoutSize = layoutSize,
        _hitTestSize = hitTestSize;

  Axis _direction;
  Axis get direction => _direction;
  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  double _layoutSize;
  double get layoutSize => _layoutSize;
  set layoutSize(double value) {
    if (_layoutSize == value) return;
    _layoutSize = value;
    markNeedsLayout();
  }

  double _hitTestSize;
  double get hitTestSize => _hitTestSize;
  set hitTestSize(double value) {
    if (_hitTestSize == value) return;
    _hitTestSize = value;
    // We don't necessarily need layout, but a repaint or hit test update.
  }

  @override
  void performLayout() {
    if (child != null) {
      final childConstraints = direction == Axis.horizontal
          ? constraints.copyWith(minWidth: 0, maxWidth: hitTestSize)
          : constraints.copyWith(minHeight: 0, maxHeight: hitTestSize);
      child!.layout(childConstraints, parentUsesSize: true);

      size = direction == Axis.horizontal
          ? Size(layoutSize, constraints.maxHeight)
          : Size(constraints.maxWidth, layoutSize);
    } else {
      size = direction == Axis.horizontal
          ? Size(layoutSize, constraints.maxHeight)
          : Size(constraints.maxWidth, layoutSize);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      final dx = direction == Axis.horizontal
          ? (layoutSize - child!.size.width) / 2
          : 0.0;
      final dy = direction == Axis.vertical
          ? (layoutSize - child!.size.height) / 2
          : 0.0;

      context.paintChild(child!, offset + Offset(dx, dy));
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final hitTestRect = direction == Axis.horizontal
        ? Rect.fromLTWH(
            (layoutSize - hitTestSize) / 2, 0, hitTestSize, size.height)
        : Rect.fromLTWH(
            0, (layoutSize - hitTestSize) / 2, size.width, hitTestSize);

    if (hitTestRect.contains(position)) {
      if (hitTestChildren(result, position: position) ||
          hitTestSelf(position)) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child != null) {
      final dx = direction == Axis.horizontal
          ? (layoutSize - child!.size.width) / 2
          : 0.0;
      final dy = direction == Axis.vertical
          ? (layoutSize - child!.size.height) / 2
          : 0.0;

      final childPosition = position - Offset(dx, dy);

      final isHit = result.addWithPaintOffset(
        offset: Offset(dx, dy),
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          return child!.hitTest(result, position: childPosition);
        },
      );
      return isHit;
    }
    return false;
  }
}
