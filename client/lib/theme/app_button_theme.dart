import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

typedef AppButtonThemes = ({
  FilledButtonThemeData filled,
  OutlinedButtonThemeData outlined,
  ElevatedButtonThemeData elevated,
  TextButtonThemeData text,
});

/// White label/icon on primary-filled chrome (light + dark; ignores [onPrimary]
/// which is black for amber/forest seeds).
const Color kFilledButtonForeground = Colors.white;

/// Hand cursor for interactive controls; arrow when disabled.
///
/// Material's default `WidgetStateMouseCursor.adaptiveClickable` resolves to an
/// arrow on non-web desktop, so we opt every button family into a hand pointer.
final WidgetStateProperty<MouseCursor> kTpClickableMouseCursor =
    WidgetStateProperty.resolveWith((states) {
  if (states.contains(WidgetState.disabled)) {
    return SystemMouseCursors.basic;
  }
  return SystemMouseCursors.click;
});

/// Geometry for [size] (default medium = theme). Does not set foreground —
/// filled chrome uses [kFilledButtonForeground]; outline/text use onSurface.
///
/// Pass as `style:` on a button to opt into small/large without fighting the
/// global theme (widget style merges over theme).
ButtonStyle appButtonStyle(
  BuildContext context, {
  TpControlSize size = TpControlSize.medium,
}) {
  final control = context.tpControl;
  return _buttonGeometry(
    metrics: control.metricsFor(size),
    radius: control.radius,
  );
}

AppButtonThemes buildAppButtonThemes({
  required TpControlMetrics control,
  required ThemeData flexTheme,
}) {
  final geometry = _buttonGeometry(
    metrics: control.medium,
    radius: control.radius,
  );
  final fallbackShape = ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(control.radius)),
    ),
  );

  ButtonStyle merge(ButtonStyle? base, {Color? foreground}) {
    var style = base == null ? fallbackShape.merge(geometry) : base.merge(geometry);
    if (foreground != null) {
      style = style.merge(
        ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return foreground.withValues(alpha: 0.38);
            }
            return foreground;
          }),
        ),
      );
    }
    return style;
  }

  final onSurface = flexTheme.colorScheme.onSurface;

  return (
    filled: FilledButtonThemeData(
      style: merge(
        flexTheme.filledButtonTheme.style,
        foreground: kFilledButtonForeground,
      ),
    ),
    outlined: OutlinedButtonThemeData(
      style: merge(flexTheme.outlinedButtonTheme.style, foreground: onSurface),
    ),
    elevated: ElevatedButtonThemeData(
      style: merge(
        flexTheme.elevatedButtonTheme.style,
        foreground: kFilledButtonForeground,
      ),
    ),
    text: TextButtonThemeData(
      style: merge(flexTheme.textButtonTheme.style, foreground: onSurface),
    ),
  );
}

/// Compact button track (independent of [TpControlMetrics.input]).
///
/// Horizontal padding only; [minimumSize]/[maximumSize] height from button
/// metrics. Outline inputs use a taller [TpControlMetrics.input] track so their
/// contentPadding is not collapsed.
///
/// Shape is a modest rounded rect. Foreground is applied per button kind in
/// [buildAppButtonThemes].
ButtonStyle _buttonGeometry({
  required TpControlSizeMetrics metrics,
  required double radius,
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
    mouseCursor: kTpClickableMouseCursor,
  );
}
