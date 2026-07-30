import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../pages/floating_workspace/floating_workspace_toggle_metrics.dart';

/// Panel size + position relative to the **app host** (bottom-right insets).
///
/// Unlike absolute left/top, this stays put relative to the window when the
/// user resizes TeamPilot — same model as [FloatingWorkspaceState.toggleOffset].
class FloatingPanelPlacement extends Equatable {
  const FloatingPanelPlacement({
    required this.width,
    required this.height,
    required this.rightInset,
    required this.bottomInset,
  });

  /// Preferred open size near the toggle (insets match default toggle clearance).
  static const FloatingPanelPlacement defaultNearToggle = FloatingPanelPlacement(
    width: 720,
    height: 480,
    rightInset: kFloatingWorkspaceToggleDefaultRight,
    // toggle bottom inset + toggle height + gap
    bottomInset: kFloatingWorkspaceToggleDefaultBottom +
        kFloatingWorkspaceToggleSize +
        kFloatingWorkspacePanelToggleGap,
  );

  final double width;
  final double height;

  /// Distance from host right edge to the panel's right edge.
  final double rightInset;

  /// Distance from host bottom edge to the panel's bottom edge.
  final double bottomInset;

  factory FloatingPanelPlacement.fromRect(Rect rect, Size host) {
    return FloatingPanelPlacement(
      width: rect.width,
      height: rect.height,
      rightInset: host.width - rect.right,
      bottomInset: host.height - rect.bottom,
    );
  }

  FloatingPanelPlacement copyWith({
    double? width,
    double? height,
    double? rightInset,
    double? bottomInset,
  }) {
    return FloatingPanelPlacement(
      width: width ?? this.width,
      height: height ?? this.height,
      rightInset: rightInset ?? this.rightInset,
      bottomInset: bottomInset ?? this.bottomInset,
    );
  }

  /// Resolves to a host-local [Rect], clamped to [host] and minimum size.
  Rect resolve(
    Size host, {
    double minWidth = 320,
    double minHeight = 240,
  }) {
    if (host.width <= 0 || host.height <= 0) {
      return Rect.fromLTWH(0, 0, width, height);
    }
    final w = width.clamp(minWidth, host.width).toDouble();
    final h = height.clamp(minHeight, host.height).toDouble();
    final maxRight = math.max(0.0, host.width - w);
    final maxBottom = math.max(0.0, host.height - h);
    final right = rightInset.clamp(0.0, maxRight).toDouble();
    final bottom = bottomInset.clamp(0.0, maxBottom).toDouble();
    final left = host.width - right - w;
    final top = host.height - bottom - h;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  List<Object?> get props => [width, height, rightInset, bottomInset];
}
