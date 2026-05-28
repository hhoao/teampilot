import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/member_presence.dart';

/// Theme-adaptive 12px dot for member list presence (no [Semantics] here —
/// parent [ListTile] owns accessibility).
class MemberPresenceIndicator extends StatefulWidget {
  const MemberPresenceIndicator({
    required this.presence,
    super.key,
  });

  final MemberPresence presence;

  @override
  State<MemberPresenceIndicator> createState() => _MemberPresenceIndicatorState();
}

class _MemberPresenceIndicatorState extends State<MemberPresenceIndicator>
    with SingleTickerProviderStateMixin {
  static const _pulseDuration = Duration(milliseconds: 1000);
  static const _minAlpha = 0.18;
  static const _maxAlpha = 1.0;
  static const _minScale = 0.88;
  static const _maxScale = 1.14;
  static const _dotSize = 12.0;

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _syncPulse();
  }

  @override
  void didUpdateWidget(MemberPresenceIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presence.isWorking != widget.presence.isWorking) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.presence.isWorking) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      return;
    }
    _pulseController.stop();
    _pulseController.value = _maxAlpha;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.presence.isWorking) {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value;
            final coreAlpha = _minAlpha + (_maxAlpha - _minAlpha) * t;
            final scale = _minScale + (_maxScale - _minScale) * t;
            return _WorkingPresenceDot(
              primary: cs.primary,
              coreAlpha: coreAlpha,
              glowT: t,
              scale: scale,
            );
          },
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: _dotSize,
      height: _dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _staticDotColor(cs, widget.presence),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
    );
  }
}

/// Pulsing working dot: stronger alpha swing, scale, and primary glow.
class _WorkingPresenceDot extends StatelessWidget {
  const _WorkingPresenceDot({
    required this.primary,
    required this.coreAlpha,
    required this.glowT,
    required this.scale,
  });

  final Color primary;
  final double coreAlpha;
  final double glowT;
  final double scale;

  static const _boxSize = 16.0;

  @override
  Widget build(BuildContext context) {
    final dotSize = _MemberPresenceIndicatorState._dotSize;
    return SizedBox(
      width: _boxSize,
      height: _boxSize,
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: coreAlpha),
              border: Border.all(
                color: primary.withValues(alpha: 0.35 + 0.65 * glowT),
                width: 1.25,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.15 + 0.55 * glowT),
                  blurRadius: 2 + 5 * glowT,
                  spreadRadius: 0.5 + 2.5 * glowT,
                ),
              ],
            ),
            child: SizedBox(width: dotSize, height: dotSize),
          ),
        ),
      ),
    );
  }
}

Color _staticDotColor(ColorScheme cs, MemberPresence presence) {
  if (presence.isIdle) {
    return cs.secondary;
  }
  if (presence.isConnecting) {
    return cs.onSurfaceVariant.withValues(alpha: 0.75);
  }
  return cs.onSurfaceVariant.withValues(alpha: 0.55);
}

String memberPresenceStatusLabel(
  AppLocalizations l10n,
  MemberPresence presence,
) {
  if (presence.isWorking) return l10n.memberPresenceWorking;
  if (presence.isIdle) return l10n.memberPresenceIdle;
  if (presence.isConnecting) return l10n.memberPresenceConnecting;
  return l10n.memberPresenceOffline;
}
