import 'package:flutter/material.dart';

/// Deterministic accent color for a team, derived from a stable seed (key/name)
/// so the same team always reads with the same identity color. Saturation and
/// lightness are tuned per [brightness] to stay legible against either surface.
Color teamAccentColor(String seed, Brightness brightness) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final isDark = brightness == Brightness.dark;
  return HSLColor.fromAHSL(
    1,
    hue,
    isDark ? 0.45 : 0.58,
    isDark ? 0.60 : 0.46,
  ).toColor();
}

/// A rounded monogram tile carrying a team's identity accent + first glyph.
class TeamMonogram extends StatelessWidget {
  const TeamMonogram({
    super.key,
    required this.seed,
    required this.label,
    this.size = 40,
    this.radius = 11,
  });

  /// Stable seed for the accent color (use the team key for stability).
  final String seed;

  /// Human-readable name the glyph is taken from.
  final String label;
  final double size;
  final double radius;

  String get _glyph {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = teamAccentColor(seed, Theme.of(context).brightness);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.alphaBlend(Colors.black.withValues(alpha: 0.20), accent),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        _glyph,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          height: 1,
        ),
      ),
    );
  }
}
