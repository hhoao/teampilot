import 'package:flutter/material.dart';

import 'multi_split_view.dart';

/// TeamPilot defaults for [MultiSplitView] dividers (matches legacy [ResizableSplitView]).
class TeamPilotSplitTheme extends StatelessWidget {
  const TeamPilotSplitTheme({
    super.key,
    required this.child,
    this.dividerThickness = 1,
    this.dividerColor,
  });

  final Widget child;
  final double dividerThickness;
  final Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        dividerColor ?? (isDark ? Colors.white12 : const Color(0xFFE5E7EB));
    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerThickness: dividerThickness,
        dividerPainter: DividerPainters.background(color: color),
      ),
      child: child,
    );
  }
}

/// Two-pane horizontal split backed by [MultiSplitView].
///
/// The leading pane uses a fixed [Area.size]; the trailing pane uses flex.
/// [onWidthChanged] is invoked when the user finishes dragging a divider.
class ResizableSplitView extends StatefulWidget {
  const ResizableSplitView({
    super.key,
    required this.left,
    required this.right,
    this.initialLeftWidth = 180,
    this.initialLeftFraction,
    this.minLeftWidth = 120,
    this.maxLeftWidth = 500,
    this.dividerWidth = 1,
    this.onWidthChanged,
  });

  final Widget left;
  final Widget right;
  final double initialLeftWidth;
  final double? initialLeftFraction;
  final double minLeftWidth;
  final double maxLeftWidth;
  final double dividerWidth;
  final ValueChanged<double>? onWidthChanged;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  static const _leadingId = 'leading';
  static const _trailingId = 'trailing';

  late final MultiSplitViewController _controller;
  late Area _leading;
  late Area _trailing;
  bool _fractionInitialized = false;

  @override
  void initState() {
    super.initState();
    _leading = Area(
      id: _leadingId,
      size: widget.initialLeftWidth,
      min: widget.minLeftWidth,
      max: _finiteMax(widget.maxLeftWidth),
    );
    _trailing = Area(id: _trailingId, flex: 1);
    _controller = MultiSplitViewController(areas: [_leading, _trailing]);
  }

  @override
  void didUpdateWidget(ResizableSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _leading.min = widget.minLeftWidth;
    if (widget.initialLeftWidth != oldWidget.initialLeftWidth &&
        widget.initialLeftFraction == null) {
      _leading.size = widget.initialLeftWidth;
    }
  }

  double? _finiteMax(double max) => max.isFinite ? max : null;

  void _syncAreas(double availableWidth) {
    _leading.builder = (_, __) => widget.left;
    _trailing.builder = (_, __) => widget.right;

    final divider = widget.dividerWidth;
    final cap = (availableWidth - divider).clamp(
      widget.minLeftWidth,
      availableWidth,
    );
    final effectiveMax = widget.maxLeftWidth.isFinite
        ? widget.maxLeftWidth.clamp(widget.minLeftWidth, cap)
        : cap;
    _leading.max = effectiveMax;

    if (!_fractionInitialized && widget.initialLeftFraction != null) {
      _leading.size = (availableWidth * widget.initialLeftFraction!).clamp(
        widget.minLeftWidth,
        effectiveMax,
      );
      _fractionInitialized = true;
    }
  }

  void _reportLeadingWidth() {
    final width = _leading.size;
    if (width != null) {
      widget.onWidthChanged?.call(width);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _syncAreas(constraints.maxWidth);
        return TeamPilotSplitTheme(
          dividerThickness: widget.dividerWidth,
          child: MultiSplitView(
            axis: Axis.horizontal,
            controller: _controller,
            onDividerDragEnd: (_) => _reportLeadingWidth(),
          ),
        );
      },
    );
  }
}

/// Vertical split: fixed-height top pane above a flex bottom pane.
class ResizableVerticalSplitView extends StatefulWidget {
  const ResizableVerticalSplitView({
    super.key,
    required this.top,
    required this.bottom,
    this.initialTopHeight = 240,
    this.initialTopFraction,
    this.minTopHeight = 120,
    this.maxTopHeight = 800,
    this.dividerHeight = 1,
    this.onHeightChanged,
  });

  final Widget top;
  final Widget bottom;
  final double initialTopHeight;
  final double? initialTopFraction;
  final double minTopHeight;
  final double maxTopHeight;
  final double dividerHeight;
  final ValueChanged<double>? onHeightChanged;

  @override
  State<ResizableVerticalSplitView> createState() =>
      _ResizableVerticalSplitViewState();
}

class _ResizableVerticalSplitViewState
    extends State<ResizableVerticalSplitView> {
  late final MultiSplitViewController _controller;
  late Area _top;
  late Area _bottom;
  bool _fractionInitialized = false;

  @override
  void initState() {
    super.initState();
    _top = Area(
      size: widget.initialTopHeight,
      min: widget.minTopHeight,
      max: _finiteMax(widget.maxTopHeight),
    );
    _bottom = Area(flex: 1);
    _controller = MultiSplitViewController(areas: [_top, _bottom]);
  }

  double? _finiteMax(double max) => max.isFinite ? max : null;

  void _syncAreas(double availableHeight) {
    _top.builder = (_, __) => widget.top;
    _bottom.builder = (_, __) => widget.bottom;

    final cap = (availableHeight - widget.dividerHeight).clamp(
      widget.minTopHeight,
      availableHeight,
    );
    final effectiveMax = widget.maxTopHeight.isFinite
        ? widget.maxTopHeight.clamp(widget.minTopHeight, cap)
        : cap;
    _top.max = effectiveMax;

    if (!_fractionInitialized && widget.initialTopFraction != null) {
      _top.size = (availableHeight * widget.initialTopFraction!).clamp(
        widget.minTopHeight,
        effectiveMax,
      );
      _fractionInitialized = true;
    }
  }

  void _reportTopHeight() {
    final height = _top.size;
    if (height != null) {
      widget.onHeightChanged?.call(height);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _syncAreas(constraints.maxHeight);
        return TeamPilotSplitTheme(
          dividerThickness: widget.dividerHeight,
          child: MultiSplitView(
            axis: Axis.vertical,
            controller: _controller,
            onDividerDragUpdate: widget.onHeightChanged == null
                ? null
                : (_) => _reportTopHeight(),
            onDividerDragEnd: (_) => _reportTopHeight(),
          ),
        );
      },
    );
  }
}

/// Vertical split: flex top pane above a fixed-height bottom pane.
///
/// [bottomHeight] is controlled by the parent (e.g. [LayoutCubit]).
/// [onBottomHeightChanged] is called while the divider is dragged.
class ResizableBottomPaneView extends StatefulWidget {
  const ResizableBottomPaneView({
    super.key,
    required this.top,
    required this.bottom,
    required this.bottomHeight,
    this.minBottomHeight = 120,
    this.maxBottomHeight = 480,
    this.dividerHeight = 1,
    this.dividerColor,
    this.onBottomHeightChanged,
  });

  final Widget top;
  final Widget bottom;
  final double bottomHeight;
  final double minBottomHeight;
  final double maxBottomHeight;
  final double dividerHeight;
  final Color? dividerColor;
  final ValueChanged<double>? onBottomHeightChanged;

  @override
  State<ResizableBottomPaneView> createState() =>
      _ResizableBottomPaneViewState();
}

class _ResizableBottomPaneViewState extends State<ResizableBottomPaneView> {
  late final MultiSplitViewController _controller;
  late Area _top;
  late Area _bottom;

  @override
  void initState() {
    super.initState();
    _top = Area(flex: 1);
    _bottom = Area(
      size: widget.bottomHeight,
      min: widget.minBottomHeight,
      max: widget.maxBottomHeight,
    );
    _controller = MultiSplitViewController(areas: [_top, _bottom]);
  }

  @override
  void didUpdateWidget(ResizableBottomPaneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bottomHeight != oldWidget.bottomHeight) {
      _bottom.size = widget.bottomHeight.clamp(
        widget.minBottomHeight,
        widget.maxBottomHeight,
      );
    }
    _bottom.min = widget.minBottomHeight;
    _bottom.max = widget.maxBottomHeight;
  }

  void _syncBuilders() {
    _top.builder = (_, __) => widget.top;
    _bottom.builder = (_, __) => widget.bottom;
  }

  void _reportBottomHeight() {
    final height = _bottom.size;
    if (height != null) {
      widget.onBottomHeightChanged?.call(height);
    }
  }

  Color _dividerColor(BuildContext context) {
    if (widget.dividerColor != null) {
      return widget.dividerColor!;
    }
    return Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45);
  }

  @override
  Widget build(BuildContext context) {
    _syncBuilders();
    return TeamPilotSplitTheme(
      dividerThickness: widget.dividerHeight,
      dividerColor: _dividerColor(context),
      child: MultiSplitView(
        axis: Axis.vertical,
        controller: _controller,
        onDividerDragUpdate: (_) => _reportBottomHeight(),
      ),
    );
  }
}

/// Horizontal split: flex leading pane and a fixed-width trailing pane.
///
/// [trailingWidth] is controlled by the parent. [onTrailingWidthChanged] is
/// called while the divider is dragged. Dragging the divider right increases
/// the trailing width.
class ResizableTrailingPaneView extends StatefulWidget {
  const ResizableTrailingPaneView({
    super.key,
    required this.leading,
    required this.trailing,
    required this.trailingWidth,
    this.minTrailingWidth = 140,
    this.maxTrailingWidth = 420,
    this.dividerWidth = 4,
    this.dividerColor,
    this.onTrailingWidthChanged,
  });

  final Widget leading;
  final Widget trailing;
  final double trailingWidth;
  final double minTrailingWidth;
  final double maxTrailingWidth;
  final double dividerWidth;
  final Color? dividerColor;
  final ValueChanged<double>? onTrailingWidthChanged;

  @override
  State<ResizableTrailingPaneView> createState() =>
      _ResizableTrailingPaneViewState();
}

class _ResizableTrailingPaneViewState extends State<ResizableTrailingPaneView> {
  late final MultiSplitViewController _controller;
  late Area _leading;
  late Area _trailing;

  @override
  void initState() {
    super.initState();
    _leading = Area(flex: 1);
    _trailing = Area(
      size: widget.trailingWidth,
      min: widget.minTrailingWidth,
      max: widget.maxTrailingWidth,
    );
    _controller = MultiSplitViewController(areas: [_leading, _trailing]);
  }

  @override
  void didUpdateWidget(ResizableTrailingPaneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trailingWidth != oldWidget.trailingWidth) {
      _trailing.size = widget.trailingWidth.clamp(
        widget.minTrailingWidth,
        widget.maxTrailingWidth,
      );
    }
    _trailing.min = widget.minTrailingWidth;
    _trailing.max = widget.maxTrailingWidth;
  }

  void _syncBuilders() {
    _leading.builder = (_, __) => widget.leading;
    _trailing.builder = (_, __) => widget.trailing;
  }

  void _reportTrailingWidth() {
    final width = _trailing.size;
    if (width != null) {
      widget.onTrailingWidthChanged?.call(width);
    }
  }

  Color _dividerColor(BuildContext context) {
    if (widget.dividerColor != null) {
      return widget.dividerColor!;
    }
    return Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45);
  }

  @override
  Widget build(BuildContext context) {
    _syncBuilders();
    return TeamPilotSplitTheme(
      dividerThickness: widget.dividerWidth,
      dividerColor: _dividerColor(context),
      child: MultiSplitView(
        axis: Axis.horizontal,
        controller: _controller,
        onDividerDragUpdate: (_) => _reportTrailingWidth(),
      ),
    );
  }
}
