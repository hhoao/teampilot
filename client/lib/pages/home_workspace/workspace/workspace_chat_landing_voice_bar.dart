import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'workspace_chat_landing_palette.dart';

String formatComposeVoiceElapsed(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Waveform dots + timer shown while compose voice input is active.
class ComposeVoiceRecordingStatus extends StatelessWidget {
  const ComposeVoiceRecordingStatus({
    required this.palette,
    required this.elapsed,
    required this.soundLevel,
    required this.cancelTooltip,
    required this.stopTooltip,
    required this.onCancel,
    required this.onStop,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final Duration elapsed;
  final double soundLevel;
  final String cancelTooltip;
  final String stopTooltip;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ComposeVoiceLevelDots(
          soundLevel: soundLevel,
          color: cs.primary.withValues(alpha: 0.82),
        ),
        SizedBox(width: spacing.md),
        Text(
          formatComposeVoiceElapsed(elapsed),
          style: styles.smColored(palette.muted),
        ),
        SizedBox(width: spacing.md),
        _ComposeVoiceIconButton(
          palette: palette,
          tooltip: cancelTooltip,
          icon: Icons.close_rounded,
          onTap: onCancel,
        ),
        SizedBox(width: spacing.xs),
        _ComposeVoiceStopButton(
          palette: palette,
          tooltip: stopTooltip,
          onTap: onStop,
        ),
      ],
    );
  }
}

class _ComposeVoiceLevelDots extends StatefulWidget {
  const _ComposeVoiceLevelDots({
    required this.soundLevel,
    required this.color,
  });

  final double soundLevel;
  final Color color;

  @override
  State<_ComposeVoiceLevelDots> createState() => _ComposeVoiceLevelDotsState();
}

class _ComposeVoiceLevelDotsState extends State<_ComposeVoiceLevelDots>
    with SingleTickerProviderStateMixin {
  static const _dotCount = 7;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final level = widget.soundLevel.clamp(0.0, 10.0) / 10.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _dotCount; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _VoiceDot(
                  color: widget.color,
                  scale: _dotScale(index: i, level: level, phase: _pulse.value),
                ),
              ),
          ],
        );
      },
    );
  }

  double _dotScale({
    required int index,
    required double level,
    required double phase,
  }) {
    final wave = math.sin((phase * math.pi * 2) + (index * 0.85));
    final baseline = index % 3 == 0 ? 0.55 : 0.42;
    return (baseline + (wave * 0.18) + (level * 0.35)).clamp(0.35, 1.0);
  }
}

class _VoiceDot extends StatelessWidget {
  const _VoiceDot({required this.color, required this.scale});

  final Color color;
  final double scale;

  static const double _size = 8;

  @override
  Widget build(BuildContext context) {
    final diameter = _size * scale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ComposeVoiceIconButton extends StatelessWidget {
  const _ComposeVoiceIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.appIconSizes;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Icon(icon, size: icons.md, color: palette.muted),
          ),
        ),
      ),
    );
  }
}

class _ComposeVoiceStopButton extends StatelessWidget {
  const _ComposeVoiceStopButton({
    required this.palette,
    required this.tooltip,
    required this.onTap,
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final VoidCallback onTap;

  static const double _outer = 36;
  static const double _inner = 14;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.chipFill,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: palette.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: _outer,
            height: _outer,
            child: Center(
              child: Container(
                width: _inner,
                height: _inner,
                decoration: BoxDecoration(
                  color: const Color(0xFFE85D5D),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
