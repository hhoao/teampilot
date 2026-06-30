import 'package:flutter/material.dart';

/// Fade + horizontal slide entry motion using compositor transforms only.
///
/// Unlike [SlideTransition] or flutter_animate [AnimateEffect.slideX], the
/// [child] subtree is built once and not relayout on every animation tick.
class PaneEntryAnimation extends StatelessWidget {
  const PaneEntryAnimation({
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.slideFraction = 0.025,
    super.key,
  });

  final Widget child;
  final Duration duration;
  final double slideFraction;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final opacity = Curves.easeOut.transform(t);
        final dx = MediaQuery.sizeOf(context).width * slideFraction * (1 - t);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: child,
    );
  }
}

/// [AnimatedSwitcher] transition with fade + compositor slide (no [SlideTransition]).
Widget paneSwitcherStructuralTransition(
  Widget child,
  Animation<double> animation,
  BuildContext context,
) {
  return FadeTransition(
    opacity: animation,
    child: AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final slide = Curves.easeOutCubic.transform(animation.value);
        final dx = MediaQuery.sizeOf(context).width * 0.025 * (1 - slide);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    ),
  );
}
