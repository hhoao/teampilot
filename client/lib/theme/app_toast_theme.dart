import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import 'app_spacing.dart';
import 'workspace_surface_layers.dart';

/// Default toast corner radius — matches [_subThemes.defaultRadius] in app_theme.
const double kAppToastBorderRadius = 10;

/// Desktop toast max width.
const double kAppToastMaxWidth = 400;

/// Maps TeamPilot semantic variants to toastification built-in types.
ToastificationType toastificationTypeFor(AppToastVariant variant) =>
    switch (variant) {
      AppToastVariant.info => ToastificationType.info,
      AppToastVariant.success => ToastificationType.success,
      AppToastVariant.warning => ToastificationType.warning,
      AppToastVariant.error => ToastificationType.error,
    };

/// Semantic toast kinds for [AppToast].
enum AppToastVariant { info, success, warning, error }

/// Default auto-dismiss duration per variant.
Duration defaultAppToastDuration(AppToastVariant variant, {bool hasAction = false}) {
  if (hasAction) return const Duration(seconds: 8);
  return switch (variant) {
    AppToastVariant.success => const Duration(seconds: 2),
    AppToastVariant.info => const Duration(seconds: 3),
    AppToastVariant.warning => const Duration(seconds: 4),
    AppToastVariant.error => const Duration(seconds: 5),
  };
}

/// Accent color for icon and action label.
Color appToastAccentColor(ColorScheme scheme, AppToastVariant variant) =>
    switch (variant) {
      AppToastVariant.info => scheme.primary,
      AppToastVariant.success => scheme.secondary,
      AppToastVariant.warning => scheme.primary,
      AppToastVariant.error => scheme.error,
    };

/// Global toastification defaults for [ToastificationWrapper].
ToastificationConfig buildAppToastificationConfig() {
  return ToastificationConfig(
    alignment: Platform.isAndroid
        ? Alignment.bottomCenter
        : AlignmentDirectional.bottomEnd,
    itemWidth: kAppToastMaxWidth,
    maxToastLimit: 1,
    animationDuration: const Duration(milliseconds: 200),
    maxTitleLines: 3,
    maxDescriptionLines: 1,
    marginBuilder: (context, alignment) {
      final spacing = AppSpacingTheme.fromContext(context);
      final bottom = spacing.lg + MediaQuery.viewPaddingOf(context).bottom;
      final horizontal = spacing.lg;
      final y = alignment.resolve(Directionality.of(context)).y;
      if (y >= 0.5) {
        return EdgeInsets.only(
          left: horizontal,
          right: horizontal,
          bottom: bottom,
        );
      }
      return EdgeInsets.only(top: spacing.lg);
    },
  );
}

/// Visual parameters for a single toast, derived from the active [ThemeData].
({
  Color backgroundColor,
  Color foregroundColor,
  Color accentColor,
  BorderSide borderSide,
  BorderRadius borderRadius,
  List<BoxShadow> boxShadow,
  EdgeInsetsGeometry padding,
}) appToastStyleFor(
  ThemeData theme,
  AppToastVariant variant,
) {
  final scheme = theme.colorScheme;
  final accent = appToastAccentColor(scheme, variant);
  final isDark = theme.brightness == Brightness.dark;

  return (
    backgroundColor: scheme.workspaceCard,
    foregroundColor: scheme.onSurface,
    accentColor: accent,
    borderSide: BorderSide(
      color: scheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.55),
    ),
    borderRadius: BorderRadius.circular(kAppToastBorderRadius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}
