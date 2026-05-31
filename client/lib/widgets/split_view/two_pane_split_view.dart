import 'package:flutter/material.dart';

import '../resizable_split_view.dart';

/// Two-pane split backed by [ResizableSplitView] ([first] pane is resizable).
class TwoPaneSplitView extends StatelessWidget {
  const TwoPaneSplitView({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    required this.minSize,
    required this.minSecondarySize,
    required this.maxSize,
    this.initialSize,
    this.initialFraction,
    this.dividerThickness = 1,
    this.dividerHitBuffer = 5,
    this.onSizeChanged,
  }) : assert(
         initialSize != null || initialFraction != null,
         'Provide initialSize or initialFraction',
       );

  final Axis axis;
  final Widget first;
  final Widget second;
  final double? initialSize;
  final double? initialFraction;
  final double minSize;
  final double minSecondarySize;
  final double maxSize;
  final double dividerThickness;
  final double dividerHitBuffer;
  final ValueChanged<double>? onSizeChanged;

  @override
  Widget build(BuildContext context) {
    return ResizableSplitView(
      axis: axis,
      first: first,
      second: second,
      initialPrimarySize: initialSize ?? minSize,
      initialPrimaryFraction: initialFraction,
      minPrimarySize: minSize,
      minSecondarySize: minSecondarySize,
      maxPrimarySize: maxSize,
      dividerThickness: dividerThickness,
      dividerHitBuffer: dividerHitBuffer,
      onPrimarySizeChanged: onSizeChanged,
    );
  }
}
