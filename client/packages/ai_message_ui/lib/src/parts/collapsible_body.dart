import 'package:flutter/material.dart';

/// Duration shared by every folding block (tool cards, reasoning, outlines).
const Duration kAiCollapseDuration = Duration(milliseconds: 200);

/// Curve shared by every folding block.
const Curve kAiCollapseCurve = Curves.easeInOut;

/// Eases a foldable block body open and closed.
///
/// Only the fold itself animates: while the block is open the body lays out at
/// its natural height, so content that grows afterwards (streamed reasoning,
/// a nested block opening) does not re-animate this wrapper — nesting these
/// would otherwise compound into animations that never settle.
///
/// A collapsed block mounts [SizedBox.shrink] once the close animation ends,
/// keeping the body out of layout at rest; [child] is only mounted during the
/// open state (and the closing animation).
class AiCollapsibleBody extends StatefulWidget {
  const AiCollapsibleBody({
    required this.open,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.duration = kAiCollapseDuration,
    this.curve = kAiCollapseCurve,
    super.key,
  });

  final bool open;
  final Widget child;

  /// Pins the body to the top edge while it grows/shrinks.
  final AlignmentGeometry alignment;
  final Duration duration;
  final Curve curve;

  @override
  State<AiCollapsibleBody> createState() => _AiCollapsibleBodyState();
}

class _AiCollapsibleBodyState extends State<AiCollapsibleBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.open ? 1 : 0,
  );
  late CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  @override
  void initState() {
    super.initState();
    // The controller's own rebuilds stop at sizeFactor 0; the body still has
    // to be dropped from the tree, which only this state can do.
    _controller.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AiCollapsibleBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curve != widget.curve) {
      _curve.dispose();
      _curve = CurvedAnimation(parent: _controller, curve: widget.curve);
    }
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.open != widget.open) {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    return SizeTransition(
      sizeFactor: _curve,
      alignment: widget.alignment,
      child: widget.child,
    );
  }
}
