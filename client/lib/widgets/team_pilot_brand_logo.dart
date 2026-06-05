import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Overrides for the three fills in [TeamPilotBrandLogo.assetPath].
///
/// Omitted shades use [TeamPilotBrandLogoColors.fromColorScheme] for that slot.
class TeamPilotBrandLogoColors {
  const TeamPilotBrandLogoColors({
    this.shadeDark,
    this.shadeMid,
    this.shadeLight,
  });

  /// Darkest ribbon segment (`#4770DC` in the asset).
  final Color? shadeDark;

  /// Middle segment (`#6F94F4`).
  final Color? shadeMid;

  /// Lightest segment (`#97B4FF`).
  final Color? shadeLight;

  static const Color assetShadeDark = Color(0xFF4770DC);
  static const Color assetShadeMid = Color(0xFF6F94F4);
  static const Color assetShadeLight = Color(0xFF97B4FF);

  /// Theme-aligned three-tone palette ([ColorScheme.primary] / blend / [secondary]).
  factory TeamPilotBrandLogoColors.fromColorScheme(ColorScheme scheme) {
    return TeamPilotBrandLogoColors(
      shadeDark: scheme.primary,
      shadeMid: Color.lerp(scheme.primary, scheme.secondary, 0.5)!,
      shadeLight: scheme.secondary,
    );
  }

  TeamPilotBrandLogoColors mergeWith(TeamPilotBrandLogoColors base) {
    return TeamPilotBrandLogoColors(
      shadeDark: shadeDark ?? base.shadeDark,
      shadeMid: shadeMid ?? base.shadeMid,
      shadeLight: shadeLight ?? base.shadeLight,
    );
  }

  TeamPilotBrandLogoColors requireAll() {
    assert(
      shadeDark != null && shadeMid != null && shadeLight != null,
      'All logo shades must be resolved before rendering',
    );
    return TeamPilotBrandLogoColors(
      shadeDark: shadeDark,
      shadeMid: shadeMid,
      shadeLight: shadeLight,
    );
  }
}

/// TeamPilot brand mark (title bar, rails, etc.) from [assetPath].
///
/// By default, fills follow [ColorScheme.primary] and [ColorScheme.secondary].
/// Pass [color] for a flat monochrome mark, or [colors] to override individual
/// shades.
class TeamPilotBrandLogo extends StatelessWidget {
  const TeamPilotBrandLogo({
    this.size = 24,
    this.color,
    this.colors,
    this.gradientStart,
    this.gradientEnd,
    super.key,
  });

  static const String assetPath = 'assets/icons/icon.svg';

  final double size;

  /// Tints the whole mark to one color (skips theme three-tone mapping).
  final Color? color;

  /// Per-shade overrides; omitted shades use the active [ColorScheme].
  final TeamPilotBrandLogoColors? colors;

  /// When set (with [gradientEnd]), draws a rounded gradient plate behind the mark.
  final Color? gradientStart;
  final Color? gradientEnd;

  @override
  Widget build(BuildContext context) {
    final mark = _buildMark(context);

    final start = gradientStart;
    final end = gradientEnd;
    if (start == null && end == null) {
      return mark;
    }

    final cs = Theme.of(context).colorScheme;
    final cornerRadius = size * 7 / 24;
    final inset = size * 4 / 24;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start ?? cs.primary, end ?? cs.tertiary],
        ),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      padding: EdgeInsets.all(inset),
      child: mark,
    );
  }

  Widget _buildMark(BuildContext context) {
    if (color != null) {
      return SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final themePalette = TeamPilotBrandLogoColors.fromColorScheme(scheme);
    final palette = (colors ?? const TeamPilotBrandLogoColors())
        .mergeWith(themePalette)
        .requireAll();

    return SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorMapper: _TeamPilotBrandLogoColorMapper(palette),
    );
  }
}

final class _TeamPilotBrandLogoColorMapper extends ColorMapper {
  const _TeamPilotBrandLogoColorMapper(this.palette);

  final TeamPilotBrandLogoColors palette;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (color == TeamPilotBrandLogoColors.assetShadeDark) {
      return palette.shadeDark!;
    }
    if (color == TeamPilotBrandLogoColors.assetShadeMid) {
      return palette.shadeMid!;
    }
    if (color == TeamPilotBrandLogoColors.assetShadeLight) {
      return palette.shadeLight!;
    }
    return color;
  }
}
