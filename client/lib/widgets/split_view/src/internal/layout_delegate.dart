import 'package:flutter/widgets.dart';

import '../controller.dart';
import 'layout_constraints.dart';

class LayoutDelegate extends MultiChildLayoutDelegate {
  LayoutDelegate(
      {required this.axis,
      required this.controller,
      required this.layoutConstraints,
      required this.antiAliasingWorkaround});

  final Axis axis;
  final MultiSplitViewController controller;
  final LayoutConstraints layoutConstraints;
  final bool antiAliasingWorkaround;

  @override
  void performLayout(Size size) {
    void onAreaLayout(
        {required int index,
        required double start,
        required double thickness}) {
      if (axis == Axis.horizontal) {
        layoutChild(index,
            BoxConstraints.tightFor(width: thickness, height: size.height));
        positionChild(index, Offset(start, 0));
      } else {
        layoutChild(index,
            BoxConstraints.tightFor(width: size.width, height: thickness));
        positionChild(index, Offset(0, start));
      }
    }
    void onDividerLayout(
        {required int index,
        required double start,
        required double thickness}) {
      if (axis == Axis.horizontal) {
        layoutChild('d$index',
            BoxConstraints.tightFor(width: thickness, height: size.height));
        positionChild('d$index', Offset(start, 0));
      } else {
        layoutChild('d$index',
            BoxConstraints.tightFor(width: size.width, height: thickness));
        positionChild('d$index', Offset(0, start));
      }
    }
    layoutConstraints.performLayout(
        controller: controller,
        antiAliasingWorkaround: antiAliasingWorkaround,
        onAreaLayout: onAreaLayout,
        onDividerLayout: onDividerLayout);
  }

  @override
  bool shouldRelayout(covariant LayoutDelegate oldDelegate) {
    return true;
  }
}
