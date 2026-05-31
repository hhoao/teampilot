import 'package:flutter/material.dart';

/// Compact icon control for toolbars and list rows: square hit target, rounded
/// ink splash (AppFlowy-style).
class AppIconButton extends StatelessWidget {
  static const double kDefaultSize = 32;
  static const double kDefaultIconSize = 18;
  static const double kDefaultBorderRadius = 6;

  /// Dense toolbar preset (file tree header, terminal tabs, etc.).
  static const double kCompactSize = 28;
  static const double kCompactIconSize = 16;

  const AppIconButton({
    super.key,
    this.icon,
    this.iconWidget,
    required this.onTap,
    this.tooltip,
    this.size = kDefaultSize,
    this.iconSize = kDefaultIconSize,
    this.borderRadius = kDefaultBorderRadius,
    this.color,
    this.backgroundColor,
    this.enabled = true,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final double borderRadius;
  final Color? color;
  final Color? backgroundColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;
    final radius = BorderRadius.circular(borderRadius);

    Widget iconChild =
        iconWidget ?? Icon(icon, size: iconSize, color: effectiveColor);
    if (!enabled) {
      iconChild = IconTheme(
        data: IconThemeData(color: effectiveColor.withValues(alpha: 0.38)),
        child: iconChild,
      );
    }

    Widget child = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: backgroundColor,
      ),
      child: iconChild,
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      child = Tooltip(message: tooltip!, child: child);
    }

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: enabled ? onTap : null,
        child: child,
      ),
    );
  }
}
