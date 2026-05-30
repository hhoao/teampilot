import 'package:flutter/material.dart';

import 'multi_split_view.dart';

/// [MultiSplitView] with TeamPilot divider styling.
///
/// Constructor parameters match [MultiSplitView]; [dividerThickness],
/// [dividerColor], and [dividerHandleBuffer] configure [MultiSplitViewTheme].
class ThemedMultiSplitView extends StatelessWidget {
  const ThemedMultiSplitView({
    super.key,
    this.axis = MultiSplitView.defaultAxis,
    this.controller,
    this.dividerBuilder,
    this.onDividerDragStart,
    this.onDividerDragUpdate,
    this.onDividerDragEnd,
    this.onDividerTap,
    this.onDividerDoubleTap,
    this.resizable = true,
    this.antiAliasingWorkaround = false,
    this.pushDividers = false,
    this.initialAreas,
    this.sizeOverflowPolicy = SizeOverflowPolicy.shrinkLast,
    this.sizeUnderflowPolicy = SizeUnderflowPolicy.stretchLast,
    this.minSizeRecoveryPolicy = MinSizeRecoveryPolicy.firstToLast,
    this.fallbackWidth = 500,
    this.fallbackHeight = 500,
    this.builder,
    this.areaClipBehavior = Clip.hardEdge,
    this.dividerThickness = 1,
    this.dividerColor,
    this.dividerHandleBuffer = 5,
  });

  final Axis axis;
  final MultiSplitViewController? controller;
  final DividerBuilder? dividerBuilder;
  final OnDividerDragEvent? onDividerDragStart;
  final OnDividerDragEvent? onDividerDragUpdate;
  final OnDividerDragEvent? onDividerDragEnd;
  final DividerTapCallback? onDividerTap;
  final DividerTapCallback? onDividerDoubleTap;
  final bool resizable;
  final bool antiAliasingWorkaround;
  final bool pushDividers;
  final List<Area>? initialAreas;
  final SizeOverflowPolicy sizeOverflowPolicy;
  final SizeUnderflowPolicy sizeUnderflowPolicy;
  final MinSizeRecoveryPolicy minSizeRecoveryPolicy;
  final double fallbackWidth;
  final double fallbackHeight;
  final AreaWidgetBuilder? builder;
  final Clip areaClipBehavior;

  final double dividerThickness;
  final Color? dividerColor;
  final double dividerHandleBuffer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        dividerColor ?? (isDark ? Colors.white12 : const Color(0xFFE5E7EB));

    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerThickness: dividerThickness,
        dividerPainter: DividerPainters.background(color: color),
        dividerHandleBuffer: dividerHandleBuffer,
      ),
      child: MultiSplitView(
        key: key,
        axis: axis,
        controller: controller,
        dividerBuilder: dividerBuilder,
        onDividerDragStart: onDividerDragStart,
        onDividerDragUpdate: onDividerDragUpdate,
        onDividerDragEnd: onDividerDragEnd,
        onDividerTap: onDividerTap,
        onDividerDoubleTap: onDividerDoubleTap,
        resizable: resizable,
        antiAliasingWorkaround: antiAliasingWorkaround,
        pushDividers: pushDividers,
        initialAreas: initialAreas,
        sizeOverflowPolicy: sizeOverflowPolicy,
        sizeUnderflowPolicy: sizeUnderflowPolicy,
        minSizeRecoveryPolicy: minSizeRecoveryPolicy,
        fallbackWidth: fallbackWidth,
        fallbackHeight: fallbackHeight,
        builder: builder,
        areaClipBehavior: areaClipBehavior,
      ),
    );
  }
}
