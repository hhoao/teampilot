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

/// Positions the overlay at a fixed global offset.
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
