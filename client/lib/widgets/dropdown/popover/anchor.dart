// Portal positioning types adapted from AppFlowy UI / flutter_shadcn_ui.
// See: AppFlowy frontend/appflowy_flutter/packages/appflowy_ui/.../popover/

import 'package:flutter/material.dart';

/// Base type for [AppPortal] overlay positioning.
sealed class AppAnchorBase {
  const AppAnchorBase();
}

/// Automatically positions the overlay relative to the anchor widget.
@immutable
class AppAnchorAuto extends AppAnchorBase {
  const AppAnchorAuto({
    this.offset = Offset.zero,
    this.followTargetOnResize = true,
    this.followerAnchor = Alignment.bottomCenter,
    this.targetAnchor = Alignment.bottomCenter,
  });

  final Offset offset;
  final bool followTargetOnResize;
  final Alignment followerAnchor;
  final Alignment targetAnchor;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppAnchorAuto &&
        other.offset == offset &&
        other.followTargetOnResize == followTargetOnResize &&
        other.followerAnchor == followerAnchor &&
        other.targetAnchor == targetAnchor;
  }

  @override
  int get hashCode => Object.hash(
        offset,
        followTargetOnResize,
        followerAnchor,
        targetAnchor,
      );
}

/// Positions the overlay with explicit alignments on anchor and follower.
@immutable
class AppAnchor extends AppAnchorBase {
  const AppAnchor({
    this.childAlignment = Alignment.topLeft,
    this.overlayAlignment = Alignment.bottomLeft,
    this.offset = Offset.zero,
  });

  final Alignment childAlignment;
  final Alignment overlayAlignment;
  final Offset offset;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppAnchor &&
        other.childAlignment == childAlignment &&
        other.overlayAlignment == overlayAlignment &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(childAlignment, overlayAlignment, offset);
}

/// Extra hit-test padding on the overlay so the pointer can cross [AppAnchor.offset]
/// without leaving the [TapRegion] (avoids spurious [TapRegion.onTapOutside]).
EdgeInsets tapRegionBridgeInsetsForAnchor(AppAnchorBase anchor) {
  if (anchor is! AppAnchor) return EdgeInsets.zero;
  final offset = anchor.offset;
  final child = anchor.childAlignment;
  final target = anchor.overlayAlignment;

  var top = 0.0;
  var bottom = 0.0;
  var left = 0.0;
  var right = 0.0;

  if (child.y < target.y) {
    if (offset.dy > 0) top = offset.dy;
    if (offset.dy < 0) bottom = -offset.dy;
  } else if (child.y > target.y) {
    if (offset.dy > 0) bottom = offset.dy;
    if (offset.dy < 0) top = -offset.dy;
  }

  if (child.x < target.x) {
    if (offset.dx > 0) left = offset.dx;
    if (offset.dx < 0) right = -offset.dx;
  } else if (child.x > target.x) {
    if (offset.dx > 0) right = offset.dx;
    if (offset.dx < 0) left = -offset.dx;
  }

  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

/// Point on a rectangle for an [Alignment] (-1..1 → edges/center).
Offset alignmentPointOnRect(Size size, Alignment alignment) {
  return Offset(
    (1 + alignment.x) / 2 * size.width,
    (1 + alignment.y) / 2 * size.height,
  );
}

/// Top-left position of an auto-anchored overlay in the overlay ancestor's coords.
Offset computeAppAnchorAutoOverlayTopLeft({
  required RenderBox anchorBox,
  required RenderBox overlayAncestor,
  required Size overlaySize,
  required AppAnchorAuto anchor,
}) {
  final targetPoint = alignmentPointOnRect(anchorBox.size, anchor.targetAnchor);
  final followerPoint = alignmentPointOnRect(
    overlaySize,
    anchor.followerAnchor,
  );
  final topLeftInAnchorBox = targetPoint + anchor.offset - followerPoint;
  return anchorBox.localToGlobal(topLeftInAnchorBox, ancestor: overlayAncestor);
}

/// True when overlay size must be known before the follower alignment is stable.
bool appAnchorAutoNeedsOverlayMeasure(AppAnchorAuto anchor) {
  return anchor.followerAnchor != Alignment.topLeft;
}

/// Positions the overlay at a fixed global offset (screen coordinates).
///
/// Used for right-click menus: the menu's top-left is placed at [offset],
/// matching legacy [showMenu] / [RelativeRect] behavior (not tooltip centering).
@immutable
class AppGlobalAnchor extends AppAnchorBase {
  const AppGlobalAnchor(this.offset);

  final Offset offset;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppGlobalAnchor && other.offset == offset;
  }

  @override
  int get hashCode => offset.hashCode;
}

/// Positions a context-menu panel with its top-left at [target] (overlay-local).
class ContextMenuOverlayPositionDelegate extends SingleChildLayoutDelegate {
  const ContextMenuOverlayPositionDelegate({required this.target});

  final Offset target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size viewport, Size menuSize) {
    var x = target.dx;
    var y = target.dy;
    if (x + menuSize.width > viewport.width) {
      x = viewport.width - menuSize.width;
    }
    if (y + menuSize.height > viewport.height) {
      y = target.dy - menuSize.height;
    }
    x = x.clamp(
      0.0,
      (viewport.width - menuSize.width).clamp(0.0, viewport.width),
    );
    y = y.clamp(
      0.0,
      (viewport.height - menuSize.height).clamp(0.0, viewport.height),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(ContextMenuOverlayPositionDelegate oldDelegate) {
    return target != oldDelegate.target;
  }
}
