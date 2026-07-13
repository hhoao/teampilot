import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

/// Standard control size presets for buttons (theme default is [medium]).
enum AppControlSize { small, medium, large }

/// Resolved geometry for one [AppControlSize] at the active UI scale.
@immutable
final class AppControlMetrics {
  const AppControlMetrics({
    required this.height,
    required this.minWidth,
    required this.horizontalPadding,
    required this.verticalPadding,
  });

  final double height;
  final double minWidth;
  final double horizontalPadding;
  final double verticalPadding;

  AppControlMetrics scaleBy(double m) => AppControlMetrics(
    height: height * m,
    minWidth: minWidth * m,
    horizontalPadding: horizontalPadding * m,
    verticalPadding: verticalPadding * m,
  );

  static AppControlMetrics? lerp(
    AppControlMetrics? a,
    AppControlMetrics? b,
    double t,
  ) {
    if (a == null) return b;
    if (b == null) return a;
    return AppControlMetrics(
      height: lerpDouble(a.height, b.height, t)!,
      minWidth: lerpDouble(a.minWidth, b.minWidth, t)!,
      horizontalPadding: lerpDouble(
        a.horizontalPadding,
        b.horizontalPadding,
        t,
      )!,
      verticalPadding: lerpDouble(a.verticalPadding, b.verticalPadding, t)!,
    );
  }
}

/// Shared control tokens: input + default (medium) button track, plus S/M/L
/// button presets and a non-pill corner radius.
@immutable
final class AppControlTheme extends ThemeExtension<AppControlTheme> {
  const AppControlTheme({
    required this.scale,
    required this.radius,
    required this.small,
    required this.medium,
    required this.large,
  });

  final double scale;

  /// Corner radius for outline inputs and standard buttons (not stadium/pill).
  final double radius;

  final AppControlMetrics small;
  final AppControlMetrics medium;
  final AppControlMetrics large;

  /// Default painted height (medium) — inputs and theme buttons.
  double get height => medium.height;
  double get minWidth => medium.minWidth;
  double get horizontalPadding => medium.horizontalPadding;
  double get verticalPadding => medium.verticalPadding;

  // Baselines at scale 1.0 — keep radius well below height/2 so inputs
  // are rounded rects, not stadium/pill.
  static const double radiusBase = 8;
  static const double heightBase = 24;
  static const double minWidthBase = 64;
  static const double horizontalPaddingBase = 8;
  static const double verticalPaddingBase = 8;

  static const AppControlMetrics smallBase = AppControlMetrics(
    height: 24,
    minWidth: 48,
    horizontalPadding: 8,
    verticalPadding: 6,
  );
  static const AppControlMetrics mediumBase = AppControlMetrics(
    height: heightBase,
    minWidth: minWidthBase,
    horizontalPadding: horizontalPaddingBase,
    verticalPadding: verticalPaddingBase,
  );
  static const AppControlMetrics largeBase = AppControlMetrics(
    height: 36,
    minWidth: 80,
    horizontalPadding: 16,
    verticalPadding: 10,
  );

  factory AppControlTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppControlTheme(
      scale: m,
      radius: radiusBase * m,
      small: smallBase.scaleBy(m),
      medium: mediumBase.scaleBy(m),
      large: largeBase.scaleBy(m),
    );
  }

  AppControlMetrics metricsFor(AppControlSize size) => switch (size) {
    AppControlSize.small => small,
    AppControlSize.medium => medium,
    AppControlSize.large => large,
  };

  static AppControlTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppControlTheme>() ??
      AppControlTheme.fromScale(AppTypographyScale.standard);

  @override
  AppControlTheme copyWith({
    double? scale,
    double? radius,
    AppControlMetrics? small,
    AppControlMetrics? medium,
    AppControlMetrics? large,
  }) => AppControlTheme(
    scale: scale ?? this.scale,
    radius: radius ?? this.radius,
    small: small ?? this.small,
    medium: medium ?? this.medium,
    large: large ?? this.large,
  );

  @override
  AppControlTheme lerp(ThemeExtension<AppControlTheme>? other, double t) {
    if (other is! AppControlTheme) return this;
    return AppControlTheme(
      scale: lerpDouble(scale, other.scale, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      small: AppControlMetrics.lerp(small, other.small, t)!,
      medium: AppControlMetrics.lerp(medium, other.medium, t)!,
      large: AppControlMetrics.lerp(large, other.large, t)!,
    );
  }
}

extension AppControlContext on BuildContext {
  AppControlTheme get appControl => AppControlTheme.fromContext(this);
}
