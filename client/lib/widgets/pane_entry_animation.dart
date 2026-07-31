import 'package:flutter/material.dart';

/// Fade + horizontal slide entry motion using compositor transforms only.
///
/// Unlike [SlideTransition] or flutter_animate [AnimateEffect.slideX], the
/// [child] subtree is built once and not relayout on every animation tick.
///
/// Pass a changing [restartToken] to replay the motion without remounting
/// [child] (needed when the pane stays alive across section switches).
class PaneEntryAnimation extends StatefulWidget {
  const PaneEntryAnimation({
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.slideFraction = 0.025,
    this.restartToken,
    super.key,
  });

  final Widget child;
  final Duration duration;
  final double slideFraction;

  /// When this value changes, replay the entry motion without remounting [child].
  final Object? restartToken;

  @override
  State<PaneEntryAnimation> createState() => _PaneEntryAnimationState();
}

class _PaneEntryAnimationState extends State<PaneEntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant PaneEntryAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.restartToken != oldWidget.restartToken) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final opacity = Curves.easeOut.transform(t);
        final slide = Curves.easeOutCubic.transform(t);
        final dx = MediaQuery.sizeOf(context).width * widget.slideFraction * (1 - slide);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
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
