import 'package:flutter/material.dart';

/// Lets a bounded sidebar child pass its unconsumed drag or wheel delta to the
/// scrollable that contains it. This keeps expanded session lists independently
/// scrollable while preserving the outer sidebar scroll at either edge.
class WorkspaceNestedScrollPhysics extends ClampingScrollPhysics {
  const WorkspaceNestedScrollPhysics({
    required this.outerPosition,
    super.parent,
  });

  final ScrollPosition? outerPosition;

  @override
  WorkspaceNestedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return WorkspaceNestedScrollPhysics(
      outerPosition: outerPosition,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final overscroll = super.applyBoundaryConditions(position, value);
    final outer = outerPosition;
    if (overscroll != 0 && outer != null && outer != position) {
      outer.pointerScroll(overscroll);
    }
    return overscroll;
  }
}
