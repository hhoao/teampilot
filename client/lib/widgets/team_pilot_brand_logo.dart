import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

/// Gradient square with the TeamPilot flight mark (title bar, rails, etc.).
class TeamPilotBrandLogo extends StatelessWidget {
  const TeamPilotBrandLogo({
    this.size = 24,
    this.gradientStart,
    this.gradientEnd,
    super.key,
  });

  final double size;
  final Color? gradientStart;
  final Color? gradientEnd;

  static const IconData icon = Icons.flight_takeoff_rounded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = gradientStart ?? cs.primary;
    final end = gradientEnd ?? cs.tertiary;
    final cornerRadius = size * 7 / 24;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end],
        ),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Icon(
        icon,
        size: size >= 24 ? AppIconSizes.md : AppIconSizes.sm,
        color: cs.onPrimary,
      ),
    );
  }
}
