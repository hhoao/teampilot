import 'package:flutter/material.dart';

import 'app_control_theme.dart';

typedef AppButtonThemes = ({
  FilledButtonThemeData filled,
  OutlinedButtonThemeData outlined,
  ElevatedButtonThemeData elevated,
  TextButtonThemeData text,
});

/// Geometry + onSurface foreground for [size] (default medium = theme).
///
/// Pass as `style:` on a button to opt into small/large without fighting the
/// global theme (widget style merges over theme).
ButtonStyle appButtonStyle(
  BuildContext context, {
  AppControlSize size = AppControlSize.medium,
}) {
  final control = AppControlTheme.fromContext(context);
  return _buttonGeometry(
    metrics: control.metricsFor(size),
    radius: control.radius,
    onSurface: Theme.of(context).colorScheme.onSurface,
  );
}

AppButtonThemes buildAppButtonThemes({
  required AppControlTheme control,
  required ThemeData flexTheme,
}) {
  final geometry = _buttonGeometry(
    metrics: control.medium,
    radius: control.radius,
    onSurface: flexTheme.colorScheme.onSurface,
  );
  final fallbackShape = ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(control.radius)),
    ),
  );

  ButtonStyle merge(ButtonStyle? base) =>
      base == null ? fallbackShape.merge(geometry) : base.merge(geometry);

  return (
    filled: FilledButtonThemeData(
      style: merge(flexTheme.filledButtonTheme.style),
    ),
    outlined: OutlinedButtonThemeData(
      style: merge(flexTheme.outlinedButtonTheme.style),
    ),
    elevated: ElevatedButtonThemeData(
      style: merge(flexTheme.elevatedButtonTheme.style),
    ),
    text: TextButtonThemeData(style: merge(flexTheme.textButtonTheme.style)),
  );
}

/// Compact button track (independent of [AppControlTheme.input]).
///
/// Horizontal padding only; [minimumSize]/[maximumSize] height from button
/// metrics. Outline inputs use a taller [AppControlTheme.input] track so their
/// contentPadding is not collapsed.
///
/// Labels/icons use [ColorScheme.onSurface]. Shape is a modest rounded rect.
ButtonStyle _buttonGeometry({
  required AppControlMetrics metrics,
  required double radius,
  required Color onSurface,
}) {
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(metrics.minWidth, metrics.height),
    ),
    maximumSize: WidgetStatePropertyAll(
      Size(double.infinity, metrics.height),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return onSurface.withValues(alpha: 0.38);
      }
      return onSurface;
    }),
  );
}
