import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

@immutable
final class AppControlTheme extends ThemeExtension<AppControlTheme> {
  const AppControlTheme({
    required this.scale,
    required this.height,
    required this.minWidth,
    required this.horizontalPadding,
    required this.verticalPadding,
  });

  final double scale;
  final double height;
  final double minWidth;
  final double horizontalPadding;
  final double verticalPadding;

  static const double heightBase = 40;
  static const double minWidthBase = 64;
  static const double horizontalPaddingBase = 12;
  static const double verticalPaddingBase = 13;

  factory AppControlTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppControlTheme(
      scale: m,
      height: heightBase * m,
      minWidth: minWidthBase * m,
      horizontalPadding: horizontalPaddingBase * m,
      verticalPadding: verticalPaddingBase * m,
    );
  }

  static AppControlTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppControlTheme>() ??
      AppControlTheme.fromScale(AppTypographyScale.standard);

  @override
  AppControlTheme copyWith({
    double? scale,
    double? height,
    double? minWidth,
    double? horizontalPadding,
    double? verticalPadding,
  }) => AppControlTheme(
    scale: scale ?? this.scale,
    height: height ?? this.height,
    minWidth: minWidth ?? this.minWidth,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    verticalPadding: verticalPadding ?? this.verticalPadding,
  );

  @override
  AppControlTheme lerp(ThemeExtension<AppControlTheme>? other, double t) {
    if (other is! AppControlTheme) return this;
    return AppControlTheme(
      scale: lerpDouble(scale, other.scale, t)!,
      height: lerpDouble(height, other.height, t)!,
      minWidth: lerpDouble(minWidth, other.minWidth, t)!,
      horizontalPadding: lerpDouble(horizontalPadding, other.horizontalPadding, t)!,
      verticalPadding: lerpDouble(verticalPadding, other.verticalPadding, t)!,
    );
  }
}

extension AppControlContext on BuildContext {
  AppControlTheme get appControl => AppControlTheme.fromContext(this);
}
