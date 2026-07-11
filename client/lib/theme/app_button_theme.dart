import 'package:flutter/material.dart';

import 'app_control_theme.dart';

typedef AppButtonThemes = ({
  FilledButtonThemeData filled,
  OutlinedButtonThemeData outlined,
  ElevatedButtonThemeData elevated,
  TextButtonThemeData text,
});

AppButtonThemes buildAppButtonThemes({
  required AppControlTheme control,
  required ThemeData flexTheme,
}) {
  final geometry = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(control.minWidth, control.height)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: control.horizontalPadding),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
  const stadium = ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder()));

  ButtonStyle merge(ButtonStyle? base) =>
      base == null ? stadium.merge(geometry) : base.merge(geometry);

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
