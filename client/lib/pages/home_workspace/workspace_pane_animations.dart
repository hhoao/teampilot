import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Shared entry motion for workspace-home chrome and data regions.
abstract final class WorkspacePaneAnimations {
  WorkspacePaneAnimations._();

  static const fadeDuration = Duration(milliseconds: 180);
  static const slideDuration = Duration(milliseconds: 220);

  static Animate chrome(Widget child, {required Key key}) {
    return child
        .animate(key: key)
        .fadeIn(duration: fadeDuration, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: slideDuration,
          curve: Curves.easeOutCubic,
        );
  }

  static Animate data(Widget child, {required Key key}) {
    return child
        .animate(key: key)
        .fadeIn(duration: fadeDuration, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: slideDuration,
          curve: Curves.easeOutCubic,
        );
  }
}
