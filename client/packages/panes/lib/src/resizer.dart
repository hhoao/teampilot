import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panes/src/pane_theme.dart';

/// A widget that handles drag events to resize panes.
class Resizer extends StatefulWidget {
  /// The direction of the resize drag.
  final Axis direction;

  /// Callback when resizing occurs with the delta in pixels.
  final ValueChanged<double> onResize;

  /// Callback when resizing starts.
  final VoidCallback? onResizeStart;

  /// Callback when resizing ends or is canceled.
  final VoidCallback? onResizeEnd;

  /// Callback when the resizer is double-tapped (e.g., to reset size).
  final VoidCallback? onDoubleTap;

  /// Optional override color for the resizer.
  final Color? color;

  /// The visual thickness of the resizer line.
  final double thickness;

  /// Creates a [Resizer].
  const Resizer({
    super.key,
    required this.direction,
    required this.onResize,
    this.onResizeStart,
    this.onResizeEnd,
    this.onDoubleTap,
    this.color,
    this.thickness = 4.0,
  });

  @override
  State<Resizer> createState() => _ResizerState();
}

class _ResizerState extends State<Resizer> {
  bool _isDragging = false;
  bool _isHovering = false;
  bool _isFocused = false;

  /// Track the start position for accurate total delta calculation.
  /// Using start position prevents drift from accumulated floating point errors.
  Offset? _startGlobalPosition;

  /// Accumulated delta reported to parent (for comparing with total).
  double _reportedDelta = 0;

  late final Map<ShortcutActivator, VoidCallback> _keyBindings;

  @override
  void initState() {
    super.initState();
    _keyBindings = {
      // Horizontal resizer: Left/Right arrows
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _handleKeyResize(-10, Axis.horizontal),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _handleKeyResize(10, Axis.horizontal),
      // Vertical resizer: Up/Down arrows
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _handleKeyResize(-10, Axis.vertical),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _handleKeyResize(10, Axis.vertical),
    };
  }

  void _handleKeyResize(double delta, Axis keyDirection) {
    // Only respond if the key direction matches the resizer direction
    if (widget.direction == keyDirection && delta != 0) {
      widget.onResize(delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = PaneTheme.of(context);
    final effectiveThickness = widget.thickness == 4.0
        ? theme.resizerThickness // Use theme if default
        : widget.thickness;

    // Base color from widget or theme
    final baseColor = widget.color ?? theme.resizerColor ?? Colors.grey[600]!;
    final hoverColor = theme.resizerHoverColor ?? baseColor;
    final focusedColor = theme.resizerFocusedColor ?? hoverColor;

    // Show hover color when hovering or dragging, otherwise show base color
    final effectiveColor = (_isDragging || _isHovering)
        ? hoverColor
        : (_isFocused ? focusedColor : baseColor);

    final effectiveHitTestThickness = theme.resizerHitTestThickness;

    // Inner line should also be transparent if base color is transparent
    final innerLineColor = baseColor == Colors.transparent
        ? ((_isDragging || _isHovering || _isFocused)
            ? effectiveColor.withValues(alpha: 0.5)
            : Colors.transparent)
        : (widget.color?.withValues(alpha: 0.5) ??
            theme.resizerColor?.withValues(alpha: 0.5) ??
            Colors.grey[800]);

    return CallbackShortcuts(
      bindings: _keyBindings,
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _isFocused = focused),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onDoubleTap?.call(),
          ),
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        child: MouseRegion(
          cursor: widget.direction == Axis.horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) {
              setState(() => _isDragging = true);
              _startGlobalPosition = details.globalPosition;
              _reportedDelta = 0;
              widget.onResizeStart?.call();
            },
            onPanEnd: (_) {
              setState(() => _isDragging = false);
              _startGlobalPosition = null;
              _reportedDelta = 0;
              widget.onResizeEnd?.call();
            },
            onPanCancel: () {
              setState(() => _isDragging = false);
              _startGlobalPosition = null;
              _reportedDelta = 0;
              widget.onResizeEnd?.call();
            },
            onPanUpdate: (details) {
              final currentGlobal = details.globalPosition;
              final startGlobal = _startGlobalPosition ?? currentGlobal;

              // Calculate total delta from start position (more accurate than
              // accumulating incremental deltas, prevents floating point drift)
              final totalDelta = widget.direction == Axis.horizontal
                  ? currentGlobal.dx - startGlobal.dx
                  : currentGlobal.dy - startGlobal.dy;

              // Calculate incremental delta to report (difference from what
              // we've already reported ensures no updates are lost)
              final incrementalDelta = totalDelta - _reportedDelta;
              _reportedDelta = totalDelta;

              if (incrementalDelta != 0) {
                widget.onResize(incrementalDelta);
              }
            },
            onDoubleTap: widget.onDoubleTap,
            child: Container(
              // Hit-test area (transparent)
              width: widget.direction == Axis.horizontal
                  ? effectiveHitTestThickness
                  : double.infinity,
              height: widget.direction == Axis.vertical
                  ? effectiveHitTestThickness
                  : double.infinity,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  // Visual Line
                  width: widget.direction == Axis.horizontal
                      ? effectiveThickness
                      : double.infinity,
                  height: widget.direction == Axis.vertical
                      ? effectiveThickness
                      : double.infinity,
                  color: effectiveColor,
                  child: Center(
                    child: Container(
                      // Optional inner line
                      width: widget.direction == Axis.horizontal
                          ? 1
                          : double.infinity,
                      height: widget.direction == Axis.vertical
                          ? 1
                          : double.infinity,
                      color: innerLineColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
