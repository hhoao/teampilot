import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Two-pane split with a resizable primary pane and a flexible other pane.
///
/// [axis] selects layout: horizontal (left | right) or vertical (top | bottom).
/// By default the primary pane is [first] at the start of the axis. Set
/// [primaryAtEnd] to resize [second] at the end (right or bottom) instead.
///
/// Primary extent is stored as absolute pixels. Parent resize keeps the same
/// preferred size (clamped to the new min/max), rather than scaling by fraction.
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
    this.onDragStart,
    this.onDragEnd,
  });

  final Axis axis;

  /// When true, [second] is the fixed-size pane (trailing edge); [first] flexes.
  final bool primaryAtEnd;
  final Widget first;
  final Widget second;
  final double initialPrimarySize;

  /// When set (0–1), the first layout seeds the primary pane as this fraction
  /// of the main-axis extent (still clamped). After that, the size is absolute.
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

  /// Fired when the divider drag begins. Bracket with [onDragEnd] to hold
  /// PTY resizes during continuous resize (TerminalLayoutCoordinator).
  final VoidCallback? onDragStart;

  /// Fired when the divider drag ends (pointer up or cancel).
  final VoidCallback? onDragEnd;

  bool get _isHorizontal => axis == Axis.horizontal;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  static const _dividerKey = Key('resizable-split-divider');

  /// Preferred primary extent in pixels. Display clamps to current min/max.
  double? _preferredPrimarySize;
  bool _initialized = false;

  // Fires only on drag updates so ValueListenableBuilder rebuilds without setState.
  late final _primarySizeNotifier = ValueNotifier<double?>(null);

  double? _draggingPrimarySize;
  bool _isDragging = false;

  @override
  void didUpdateWidget(ResizableSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPrimarySize != oldWidget.initialPrimarySize ||
        widget.initialPrimaryFraction != oldWidget.initialPrimaryFraction) {
      // Drag end → parent persists size → rebuild with matching initialPrimarySize.
      // Keep the preferred pixel size; do not re-seed from a fraction.
      if (_initialized &&
          _preferredPrimarySize != null &&
          (widget.initialPrimarySize - _preferredPrimarySize!).abs() < 1.0) {
        return;
      }
      _initialized = false;
      _preferredPrimarySize = null;
    }
  }

  @override
  void dispose() {
    _primarySizeNotifier.dispose();
    super.dispose();
  }

  double _availableSize(BoxConstraints constraints) =>
      widget._isHorizontal ? constraints.maxWidth : constraints.maxHeight;

  double _maxPrimarySize(double available) {
    final cap = available - widget.dividerThickness - widget.minSecondarySize;
    // Tight/zero layouts (first frame, macOS zoomed hub chrome) can make
    // [cap] negative; `clamp(0, cap)` throws ArgumentError.
    if (!(cap > 0)) return 0;
    final maxSize = widget.maxPrimarySize;
    if (!(maxSize > 0)) return 0;
    return maxSize.clamp(0.0, cap);
  }

  double _minPrimarySize(double available) {
    final maxPrimary = _maxPrimarySize(available);
    if (!(maxPrimary > 0)) return 0;
    return widget.minPrimarySize.clamp(0.0, maxPrimary);
  }

  double _seedPreferredSize(double available) {
    if (widget.initialPrimaryFraction != null) {
      // Fraction is only a one-shot seed; store the resulting pixels.
      return (available * widget.initialPrimaryFraction!.clamp(0.0, 1.0)).clamp(
        _minPrimarySize(available),
        _maxPrimarySize(available),
      );
    }
    // Keep the preferred pixel size even if the first frame must clamp display.
    return widget.initialPrimarySize;
  }

  double _displayedPrimarySize(double available) {
    if (!_initialized || _preferredPrimarySize == null) {
      _preferredPrimarySize = _seedPreferredSize(available);
      _initialized = true;
    }
    return _preferredPrimarySize!.clamp(
      _minPrimarySize(available),
      _maxPrimarySize(available),
    );
  }

  SystemMouseCursor get _resizeCursor => widget._isHorizontal
      ? SystemMouseCursors.resizeColumn
      : SystemMouseCursors.resizeRow;

  Widget _primarySizedChild(double size, Widget child) => widget._isHorizontal
      ? SizedBox(width: size, child: child)
      : SizedBox(height: size, child: child);

  Widget _divider(double thickness, Color color) => widget._isHorizontal
      ? Container(width: thickness, color: color)
      : Container(height: thickness, color: color);

  Widget _flexPane(Widget child, {required double available}) {
    final pane = ClipRect(
      child: IgnorePointer(ignoring: _isDragging, child: child),
    );
    final honorMin =
        available > widget.dividerThickness + widget.minSecondarySize;
    final minFlex = honorMin ? widget.minSecondarySize : 0.0;
    return Expanded(
      child: ConstrainedBox(
        constraints: widget._isHorizontal
            ? BoxConstraints(minWidth: minFlex)
            : BoxConstraints(minHeight: minFlex),
        child: pane,
      ),
    );
  }

  Widget _buildPanes(
    double primarySize,
    Color dividerColor, {
    required double available,
  }) {
    final flexChild = widget.primaryAtEnd ? widget.first : widget.second;
    final fixedChild = ClipRect(
      child: IgnorePointer(
        ignoring: _isDragging,
        child: widget.primaryAtEnd ? widget.second : widget.first,
      ),
    );

    final panes = [
      widget.primaryAtEnd
          ? _flexPane(flexChild, available: available)
          : _primarySizedChild(primarySize, fixedChild),
      _divider(widget.dividerThickness, dividerColor),
      widget.primaryAtEnd
          ? _primarySizedChild(primarySize, fixedChild)
          : _flexPane(flexChild, available: available),
    ];

    return widget._isHorizontal
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: panes,
          );
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
      widget.onDragStart?.call();
    }

    void onDragEnd() {
      final size = (_draggingPrimarySize ?? primarySize).clamp(
        _minPrimarySize(available),
        _maxPrimarySize(available),
      );
      setState(() {
        _preferredPrimarySize = size;
        _draggingPrimarySize = null;
        _isDragging = false;
      });
      widget.onPrimarySizeChanged?.call(size);
      widget.onDragEnd?.call();
    }

    void onDragCancel() {
      setState(() {
        _draggingPrimarySize = null;
        _isDragging = false;
      });
      widget.onDragEnd?.call();
    }

    // Hot path: only update notifier, no setState — ValueListenableBuilder
    // rebuilds the layout subtree without touching the rest of the tree.
    void onDragUpdate(double delta) {
      final dragDelta = widget.primaryAtEnd ? -delta : delta;
      final next = ((_draggingPrimarySize ?? primarySize) + dragDelta).clamp(
        _minPrimarySize(available),
        _maxPrimarySize(available),
      );
      _draggingPrimarySize = next;
      _preferredPrimarySize = next;
      _primarySizeNotifier.value = next;
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
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    // outlineVariant tracks the active palette; hardcoded gray-200 matched
    // surfaceContainer in light mode and vanished against pane backgrounds.
    final dividerColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.5 : 0.6,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = _availableSize(constraints);
        final maxPrimary = _maxPrimarySize(available);

        // ValueListenableBuilder confines drag-update rebuilds to this subtree.
        // setState (drag start/end, _isDragging) still rebuilds the full tree,
        // but those fire at most twice per drag.
        return ValueListenableBuilder<double?>(
          valueListenable: _primarySizeNotifier,
          builder: (context, _, __) {
            final currentPrimary = _displayedPrimarySize(available);
            final hitOffset = widget.primaryAtEnd
                ? (available -
                          currentPrimary -
                          widget.dividerThickness -
                          widget.dividerHitBuffer)
                      .clamp(0.0, available)
                : (currentPrimary - widget.dividerHitBuffer).clamp(
                    0.0,
                    available,
                  );
            final hitExtent =
                widget.dividerThickness + 2 * widget.dividerHitBuffer;

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildPanes(
                  currentPrimary,
                  dividerColor,
                  available: available,
                ),
                _buildDragHandle(
                  available: available,
                  primarySize: currentPrimary,
                  maxPrimary: maxPrimary,
                  hitOffset: hitOffset,
                  hitExtent: hitExtent,
                ),
                if (_isDragging)
                  Positioned.fill(child: MouseRegion(cursor: _resizeCursor)),
              ],
            );
          },
        );
      },
    );
  }
}
