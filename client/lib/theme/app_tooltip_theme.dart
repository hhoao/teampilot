import 'package:flutter/material.dart';

import 'workspace_surface_layers.dart';

/// Shared corner radius for Material [Tooltip] and [HoverTextTooltip].
const double kAppTooltipBorderRadius = 8;

/// Tooltip label style. Flutter's default [Tooltip] hardcodes 12px on desktop;
/// we use the scaled [TextTheme.bodyMedium] so tooltips follow the app's
/// text-size setting.
TextStyle appTooltipTextStyle({
  required TextTheme textTheme,
  required ColorScheme colorScheme,
}) {
  final base = textTheme.bodyMedium ?? const TextStyle();
  return base.copyWith(
    color: colorScheme.onSurface,
    height: 1.4,
  );
}

BoxDecoration appTooltipDecoration({
  required ColorScheme colorScheme,
  required Brightness brightness,
}) {
  final isDark = brightness == Brightness.dark;
  return BoxDecoration(
    color: colorScheme.workspaceInset,
    borderRadius: BorderRadius.circular(kAppTooltipBorderRadius),
    border: Border.all(
      color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.55),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.1),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

TooltipThemeData buildAppTooltipTheme({
  required TextTheme textTheme,
  required ColorScheme colorScheme,
  required Brightness brightness,
}) {
  return TooltipThemeData(
    textStyle: appTooltipTextStyle(
      textTheme: textTheme,
      colorScheme: colorScheme,
    ),
    decoration: appTooltipDecoration(
      colorScheme: colorScheme,
      brightness: brightness,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    waitDuration: const Duration(milliseconds: 700),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}
