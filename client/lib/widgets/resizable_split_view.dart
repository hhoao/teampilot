import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Two-pane split with a resizable primary pane and a flexible other pane.
///
/// [axis] selects layout: horizontal (left | right) or vertical (top | bottom).
/// By default the primary pane is [first] at the start of the axis. Set
/// [primaryAtEnd] to resize [second] at the end (right or bottom) instead.
class ResizableSplitView extends StatefulWidget {
  const ResizableSplitView({
    super.key,
    this.axis = Axis.horizontal,
    this.primaryAtEnd = false,
    required this.first,
    required this.second,
    this.initialPrimarySize = 180,
    this.initialPrimaryFraction,
    this.minPrimarySize = 120,
    this.minSecondarySize = 120,
    this.maxPrimarySize = 500,
    this.dividerThickness = 1,
    this.dividerHitBuffer = 5,
    this.onPrimarySizeChanged,
  });

  final Axis axis;

  /// When true, [second] is the fixed-size pane (trailing edge); [first] flexes.
  final bool primaryAtEnd;
  final Widget first;
  final Widget second;
  final double initialPrimarySize;

  /// When set (0–1), the first layout uses this fraction of the main-axis extent
  /// for the primary pane instead of [initialPrimarySize]. Still clamped by
  /// [minPrimarySize] / [maxPrimarySize].
  final double? initialPrimaryFraction;
  final double minPrimarySize;

  /// Minimum extent reserved for the flexible ([Expanded]) pane along [axis].
  final double minSecondarySize;
  final double maxPrimarySize;
  final double dividerThickness;

  /// Invisible extra hit area on each side of the divider, like
  /// [MultiSplitViewThemeData.dividerHandleBuffer].
  final double dividerHitBuffer;
  final ValueChanged<double>? onPrimarySizeChanged;

  bool get _isHorizontal => axis == Axis.horizontal;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  static const _dividerKey = Key('resizable-split-divider');

  // Source of truth for position; read directly during build (no notification risk).
  double? _fraction;
  bool _initialized = false;

  // Fires only on drag updates so ValueListenableBuilder rebuilds without setState.
  // The value mirrors _fraction; the content is intentionally unused in the builder.
  late final _fractionNotifier = ValueNotifier<double?>(null);

  double? _draggingPrimarySize;
  bool _isDragging = false;

  @override
  void didUpdateWidget(ResizableSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPrimarySize != oldWidget.initialPrimarySize ||
        widget.initialPrimaryFraction != oldWidget.initialPrimaryFraction) {
      _initialized = false;
      _fraction = null;
    }
  }

  @override
  void dispose() {
    _fractionNotifier.dispose();
    super.dispose();
  }

  double _availableSize(BoxConstraints constraints) =>
      widget._isHorizontal ? constraints.maxWidth : constraints.maxHeight;

  double _maxPrimarySize(double available) {
    final cap = available - widget.dividerThickness - widget.minSecondarySize;
    return widget.maxPrimarySize.clamp(0.0, cap);
  }

  double _minPrimarySize(double available) {
    final maxPrimary = _maxPrimarySize(available);
    return widget.minPrimarySize.clamp(0.0, maxPrimary);
  }

  double _primarySize(double available) {
    if (!_initialized) {
      _fraction = widget.initialPrimaryFraction != null
          ? widget.initialPrimaryFraction!.clamp(0.0, 1.0)
          : (widget.initialPrimarySize / available).clamp(0.0, 1.0);
      _initialized = true;
    }
    return (available * _fraction!).clamp(
      _minPrimarySize(available),
      _maxPrimarySize(available),
    );
  }

  double _fractionFromSize(double available, double size) =>
      (size / available).clamp(0.0, 1.0);

  SystemMouseCursor get _resizeCursor => widget._isHorizontal
      ? SystemMouseCursors.resizeColumn
      : SystemMouseCursors.resizeRow;

  Widget _primarySizedChild(double size, Widget child) => widget._isHorizontal
      ? SizedBox(width: size, child: child)
      : SizedBox(height: size, child: child);

  Widget _divider(double thickness, Color color) => widget._isHorizontal
      ? Container(width: thickness, color: color)
      : Container(height: thickness, color: color);

  Widget _flexPane(Widget child) {
    final pane = ClipRect(
      child: IgnorePointer(ignoring: _isDragging, child: child),
    );
    return Expanded(
      child: ConstrainedBox(
        constraints: widget._isHorizontal
            ? BoxConstraints(minWidth: widget.minSecondarySize)
            : BoxConstraints(minHeight: widget.minSecondarySize),
        child: pane,
      ),
    );
  }

  Widget _buildPanes(double primarySize, Color dividerColor) {
    final flexChild = widget.primaryAtEnd ? widget.first : widget.second;
    final fixedChild = ClipRect(
      child: IgnorePointer(
        ignoring: _isDragging,
        child: widget.primaryAtEnd ? widget.second : widget.first,
      ),
    );

    final panes = [
      widget.primaryAtEnd
          ? _flexPane(flexChild)
          : _primarySizedChild(primarySize, fixedChild),
      _divider(widget.dividerThickness, dividerColor),
      widget.primaryAtEnd
          ? _primarySizedChild(primarySize, fixedChild)
          : _flexPane(flexChild),
    ];

    return widget._isHorizontal
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes)
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes);
  }

  Widget _buildDragHandle({
    required double available,
    required double primarySize,
    required double maxPrimary,
    required double hitOffset,
    required double hitExtent,
  }) {
    return widget._isHorizontal
        ? Positioned(
            left: hitOffset,
            top: 0,
            bottom: 0,
            width: hitExtent,
            child: _dragHandle(
              available: available,
              primarySize: primarySize,
              maxPrimary: maxPrimary,
            ),
          )
        : Positioned(
            left: 0,
            right: 0,
            top: hitOffset,
            height: hitExtent,
            child: _dragHandle(
              available: available,
              primarySize: primarySize,
              maxPrimary: maxPrimary,
            ),
          );
  }

  Widget _dragHandle({
    required double available,
    required double primarySize,
    required double maxPrimary,
  }) {
    void onDragStart() {
      setState(() {
        _draggingPrimarySize = primarySize;
        _isDragging = true;
      });
    }

    void onDragEnd() {
      setState(() {
        _draggingPrimarySize = null;
        _isDragging = false;
      });
      widget.onPrimarySizeChanged?.call(_primarySize(available));
    }

    void onDragCancel() {
      setState(() {
        _draggingPrimarySize = null;
        _isDragging = false;
      });
    }

    // Hot path: only update notifier, no setState — ValueListenableBuilder
    // rebuilds the layout subtree without touching the rest of the tree.
    void onDragUpdate(double delta) {
      final dragDelta = widget.primaryAtEnd ? -delta : delta;
      _draggingPrimarySize =
          ((_draggingPrimarySize ?? primarySize) + dragDelta).clamp(
        _minPrimarySize(available),
        _maxPrimarySize(available),
      );
      _fraction = _fractionFromSize(available, _draggingPrimarySize!);
      _fractionNotifier.value = _fraction;
    }

    return GestureDetector(
      key: _dividerKey,
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: widget._isHorizontal ? (_) => onDragStart() : null,
      onHorizontalDragUpdate: widget._isHorizontal
          ? (details) => onDragUpdate(details.delta.dx)
          : null,
      onHorizontalDragEnd: widget._isHorizontal ? (_) => onDragEnd() : null,
      onHorizontalDragCancel: widget._isHorizontal ? onDragCancel : null,
      onVerticalDragStart: widget._isHorizontal ? null : (_) => onDragStart(),
      onVerticalDragUpdate: widget._isHorizontal
          ? null
          : (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: widget._isHorizontal ? null : (_) => onDragEnd(),
      onVerticalDragCancel: widget._isHorizontal ? null : onDragCancel,
      child: MouseRegion(cursor: _resizeCursor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE5E7EB);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = _availableSize(constraints);
        final maxPrimary = _maxPrimarySize(available);

        // ValueListenableBuilder confines drag-update rebuilds to this subtree.
        // setState (drag start/end, _isDragging) still rebuilds the full tree,
        // but those fire at most twice per drag.
        return ValueListenableBuilder<double?>(
          valueListenable: _fractionNotifier,
          builder: (context, _, __) {
            final currentPrimary = _primarySize(available);
            final hitOffset = widget.primaryAtEnd
                ? (available -
                          currentPrimary -
                          widget.dividerThickness -
                          widget.dividerHitBuffer)
                      .clamp(0.0, available)
                : (currentPrimary - widget.dividerHitBuffer).clamp(0.0, available);
            final hitExtent = widget.dividerThickness + 2 * widget.dividerHitBuffer;

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildPanes(currentPrimary, dividerColor),
                _buildDragHandle(
                  available: available,
                  primarySize: currentPrimary,
                  maxPrimary: maxPrimary,
                  hitOffset: hitOffset,
                  hitExtent: hitExtent,
                ),
                if (_isDragging)
                  Positioned.fill(
                    child: MouseRegion(cursor: _resizeCursor),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
