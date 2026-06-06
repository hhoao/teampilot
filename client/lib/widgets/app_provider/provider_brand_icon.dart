import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/app_provider_config.dart';
import 'provider_icon_registry.dart';

/// Renders a bundled cc-switch / CodePilot-aligned provider brand mark.
class ProviderBrandIcon extends StatelessWidget {
  const ProviderBrandIcon({
    required this.icon,
    this.name = '',
    this.size = 32,
    this.borderRadius = 8,
    this.showBorder = true,
    super.key,
  });

  factory ProviderBrandIcon.fromConfig(
    AppProviderConfig config, {
    double size = 32,
    double borderRadius = 8,
    bool showBorder = true,
  }) {
    return ProviderBrandIcon(
      icon: config.icon,
      name: config.name,
      size: size,
      borderRadius: borderRadius,
      showBorder: showBorder,
    );
  }

  final String icon;
  final String name;
  final double size;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = name.isNotEmpty ? name : icon;
    final asset = providerIconAssetPath(icon);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = resolveProviderIconTileBackground(cs, isDark);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(color: resolveProviderIconBorderColor(cs, isDark))
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: asset == null
          ? _InitialsFallback(
              label: label,
              color: resolveProviderIconForeground(cs, isDark),
              size: size,
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.14),
              child: _AssetIcon(path: asset),
            ),
    );
  }
}

class _AssetIcon extends StatelessWidget {
  const _AssetIcon({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(path, fit: BoxFit.contain, semanticsLabel: path);
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({
    required this.label,
    required this.color,
    required this.size,
  });

  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = _initials(label);
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.34,
        height: 1,
      ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }
}
