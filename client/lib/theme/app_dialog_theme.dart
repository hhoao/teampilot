import 'package:flutter/material.dart';

import 'workspace_surface_layers.dart';

/// Shared corner radius for [Dialog] / [AlertDialog] shells app-wide.
const double kAppDialogBorderRadius = 32;

/// Outer margin between dialog chrome and the viewport edge.
const EdgeInsets kAppDialogInsetPadding = EdgeInsets.all(24);

/// Total horizontal/vertical inset (left + right, or top + bottom).
const double kAppDialogInsetExtent = 48;

RoundedRectangleBorder appDialogShape([
  double radius = kAppDialogBorderRadius,
]) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

TextStyle appDialogTitleStyle({
  required TextTheme textTheme,
  required ColorScheme colorScheme,
}) {
  return (textTheme.titleMedium ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: colorScheme.onSurface,
  );
}

DialogThemeData buildAppDialogTheme({
  required ColorScheme colorScheme,
  required TextTheme textTheme,
}) {
  return DialogThemeData(
    clipBehavior: Clip.antiAlias,
    insetPadding: kAppDialogInsetPadding,
    shape: appDialogShape(),
    backgroundColor: colorScheme.workspaceSubtleSurface,
    surfaceTintColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    titleTextStyle: appDialogTitleStyle(
      textTheme: textTheme,
      colorScheme: colorScheme,
    ),
  );
}
