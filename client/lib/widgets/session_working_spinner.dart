import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/ui/app_keys.dart';

/// Leading status slot for a session tab / sidebar row: the animated
/// [SessionWorkingSpinner] while the session has a member in a turn, otherwise a
/// static muted dot as a placeholder (keeps the title left-aligned either way,
/// and signals an open-but-idle session). Pass colors so callers can adapt to
/// the row background (e.g. a selected sidebar tile sits on primaryContainer).
///
/// [waiting] (permission / needs-you) takes precedence over [working] and uses a
/// distinct static affordance — never the working spinner animation.
class SessionWorkingIndicator extends StatelessWidget {
  const SessionWorkingIndicator({
    super.key,
    required this.working,
    this.waiting = false,
    this.size = 13,
    this.color,
    this.idleColor,
    this.waitingColor,
  });

  final bool working;
  final bool waiting;
  final double size;
  final Color? color;
  final Color? idleColor;

  /// Attention / needs-you color; defaults to [ColorScheme.tertiary].
  final Color? waitingColor;

  @override
  Widget build(BuildContext context) {
    if (waiting) {
      return SessionWaitingMarker(size: size, color: waitingColor);
    }
    if (working) {
      return SessionWorkingSpinner(size: size, color: color);
    }
    final cs = Theme.of(context).colorScheme;
    final dot = size * 0.42;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: idleColor ?? cs.onSurfaceVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

/// Static needs-you glyph for sidebar / tab leading slots (not a spinner).
class SessionWaitingMarker extends StatelessWidget {
  const SessionWaitingMarker({super.key, this.size = 13, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.tertiary;
    return SizedBox(
      key: AppKeys.sidebarSessionWaitingMarker,
      width: size,
      height: size,
      child: Icon(
        Icons.front_hand_rounded,
        size: size,
        color: accent,
      ),
    );
  }
}

/// A 3×3 grid of rounded squares whose brightness sweeps diagonally, reading as
/// a rotating "blocks" spinner. Shown left of a session tab / sidebar list item
/// while that session has a member in [MemberAvailability.working] (members panel).
///
/// Pure UI: it animates on its own [AnimationController]; callers just mount it
/// when the session is working and unmount it when idle. Animation ticks paint
/// through [CustomPainter.repaint] — they must not rebuild widgets.
class SessionWorkingSpinner extends StatefulWidget {
  const SessionWorkingSpinner({super.key, this.size = 14, this.color});

  final double size;

  /// Defaults to the theme primary when null.
  final Color? color;

  @override
  State<SessionWorkingSpinner> createState() => _SessionWorkingSpinnerState();
}

class _SessionWorkingSpinnerState extends State<SessionWorkingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GridWavePainter(animation: _controller, color: color),
        ),
      ),
    );
  }
}

class _GridWavePainter extends CustomPainter {
  _GridWavePainter({required this.animation, required this.color})
    : super(repaint: animation);

  /// 0..1, one full diagonal sweep per cycle.
  final Animation<double> animation;
  final Color color;

  static const int _n = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.16;
    final cell = (size.width - gap * (_n - 1)) / _n;
    final radius = Radius.circular(cell * 0.3);
    final paint = Paint()..isAntiAlias = true;

    for (var row = 0; row < _n; row++) {
      for (var col = 0; col < _n; col++) {
        // Diagonal index 0..(2*(n-1)) → 0..1 phase offset; the wave travels
        // top-left → bottom-right and loops smoothly via sin.
        final cellPhase = (row + col) / ((_n - 1) * 2);
        final wave =
            0.5 + 0.5 * math.sin(2 * math.pi * (animation.value - cellPhase));
        paint.color = color.withValues(alpha: 0.22 + 0.78 * wave);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(col * (cell + gap), row * (cell + gap), cell, cell),
            radius,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridWavePainter old) =>
      old.animation != animation || old.color != color;
}
