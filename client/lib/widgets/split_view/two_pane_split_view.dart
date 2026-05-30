import 'package:flutter/material.dart';

import 'app_split_layout.dart';
import 'multi_split_view.dart';

/// Two-pane [ThemedMultiSplitView] helper for common TeamPilot layouts.
///
/// Pass [first], [second], and [fixedChildIndex] (0 or 1).
/// - Uncontrolled: [initialSize] and/or [initialFraction] (use [dynamicMax] for
///   fraction-based layouts).
/// - Controlled: [size] from the parent; [onSizeChanged] runs on drag end.
class TwoPaneSplitView extends StatefulWidget {
  const TwoPaneSplitView({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    required this.fixedChildIndex,
    required this.minSize,
    required this.maxSize,
    this.size,
    this.initialSize,
    this.initialFraction,
    this.dividerThickness = 1,
    this.onSizeChanged,
    this.dynamicMax = false,
    this.resizable = true,
    this.pushDividers = false,
  }) : assert(fixedChildIndex == 0 || fixedChildIndex == 1),
       assert(
         size != null ||
             initialSize != null ||
             (initialFraction != null && dynamicMax),
         'Provide size, initialSize, or initialFraction with dynamicMax',
       );

  final Axis axis;
  final Widget first;
  final Widget second;
  final int fixedChildIndex;
  final double? size;
  final double? initialSize;
  final double? initialFraction;
  final double minSize;
  final double maxSize;
  final double dividerThickness;
  final ValueChanged<double>? onSizeChanged;
  final bool dynamicMax;
  final bool resizable;
  final bool pushDividers;

  bool get _isControlled => size != null;

  @override
  State<TwoPaneSplitView> createState() => _TwoPaneSplitViewState();
}

class _TwoPaneSplitViewState extends State<TwoPaneSplitView> {
  late final MultiSplitViewController _controller;
  late Area _firstArea;
  late Area _secondArea;
  bool _fractionInitialized = false;

  Area get _fixedArea =>
      widget.fixedChildIndex == 0 ? _firstArea : _secondArea;

  /// Placeholder until [LayoutBuilder] applies [initialFraction].
  double get _seedFixedSize =>
      widget.size ?? widget.initialSize ?? widget.minSize;

  @override
  void initState() {
    super.initState();
    _firstArea = widget.fixedChildIndex == 0
        ? _fixedAreaConfig(_seedFixedSize)
        : _flexArea();
    _secondArea = widget.fixedChildIndex == 1
        ? _fixedAreaConfig(_seedFixedSize)
        : _flexArea();
    _controller = MultiSplitViewController(areas: [_firstArea, _secondArea]);
  }

  Area _fixedAreaConfig(double size) => Area(
    size: size,
    min: widget.minSize,
    max: _finiteMax(widget.maxSize),
  );

  Area _flexArea() => Area(flex: 1);

  double? _finiteMax(double max) => max.isFinite ? max : null;

  @override
  void didUpdateWidget(TwoPaneSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fixedArea.min = widget.minSize;
    if (!widget.dynamicMax) {
      _fixedArea.max = _finiteMax(widget.maxSize);
    }

    if (widget._isControlled) {
      if (widget.size != oldWidget.size) {
        _fixedArea.size = widget.size!.clamp(widget.minSize, widget.maxSize);
      }
      return;
    }

    if (widget.initialSize != oldWidget.initialSize &&
        widget.initialFraction == null) {
      _fixedArea.size = widget.initialSize;
    }
  }

  void _syncBuilders() {
    _firstArea.builder = (_, __) => widget.first;
    _secondArea.builder = (_, __) => widget.second;
  }

  void _syncDynamicMax(double available) {
    if (!widget.dynamicMax) {
      return;
    }

    final layoutAvailable = (available - widget.dividerThickness).clamp(
      widget.minSize,
      available,
    );
    final cap = layoutAvailable.clamp(widget.minSize, available);
    final effectiveMax = widget.maxSize.isFinite
        ? widget.maxSize.clamp(widget.minSize, cap)
        : cap;
    _fixedArea.max = effectiveMax;

    if (!_fractionInitialized && widget.initialFraction != null) {
      _fixedArea.size = (layoutAvailable * widget.initialFraction!).clamp(
        widget.minSize,
        effectiveMax,
      );
      _fractionInitialized = true;
    }
  }

  void _reportSize() {
    final fixed = _fixedArea.size;
    if (fixed != null) {
      widget.onSizeChanged?.call(fixed);
    }
  }

  Widget _buildSplit() {
    return ThemedMultiSplitView(
      axis: widget.axis,
      controller: _controller,
      dividerThickness: widget.dividerThickness,
      resizable: widget.resizable,
      pushDividers: widget.pushDividers,
      onDividerDragEnd: widget.onSizeChanged == null ? null : (_) => _reportSize(),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncBuilders();

    if (!widget.dynamicMax) {
      return _buildSplit();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        _syncDynamicMax(available);
        return _buildSplit();
      },
    );
  }
}
