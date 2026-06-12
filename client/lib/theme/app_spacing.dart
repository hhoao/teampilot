import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

/// Resolved spacing tokens on [ThemeData.extensions], derived from the active
/// [AppTypographyScale] multiplier (the app-owned UI scale). Read via
/// [BuildContext.appSpacing]; never hard-code [EdgeInsets] gaps in new code.
@immutable
final class AppSpacingTheme extends ThemeExtension<AppSpacingTheme> {
  const AppSpacingTheme({
    required this.scale,
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  /// Raw UI scale multiplier (1.0 = design baseline). Single source of truth for
  /// density; typography and icon sizes derive from the same value.
  final double scale;

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  // --- Baselines at scale 1.0 ---
  static const double xxsBase = 2;
  static const double xsBase = 4;
  static const double smBase = 8;
  static const double mdBase = 12;
  static const double lgBase = 16;
  static const double xlBase = 24;
  static const double xxlBase = 32;

  factory AppSpacingTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppSpacingTheme(
      scale: m,
      xxs: xxsBase * m,
      xs: xsBase * m,
      sm: smBase * m,
      md: mdBase * m,
      lg: lgBase * m,
      xl: xlBase * m,
      xxl: xxlBase * m,
    );
  }

  static AppSpacingTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppSpacingTheme>() ??
      AppSpacingTheme.fromScale(AppTypographyScale.standard);

  @override
  AppSpacingTheme copyWith({
    double? scale,
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) => AppSpacingTheme(
    scale: scale ?? this.scale,
    xxs: xxs ?? this.xxs,
    xs: xs ?? this.xs,
    sm: sm ?? this.sm,
    md: md ?? this.md,
    lg: lg ?? this.lg,
    xl: xl ?? this.xl,
    xxl: xxl ?? this.xxl,
  );

  @override
  AppSpacingTheme lerp(ThemeExtension<AppSpacingTheme>? other, double t) {
    if (other is! AppSpacingTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppSpacingContext on BuildContext {
  AppSpacingTheme get appSpacing => AppSpacingTheme.fromContext(this);

  /// Active app-owned UI scale multiplier (1.0 = baseline).
  double get uiScale => appSpacing.scale;
}
