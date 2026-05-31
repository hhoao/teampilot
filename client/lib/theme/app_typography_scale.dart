import 'package:flutter/material.dart';

/// Central **font size** configuration for TeamPilot UI.
///
/// Edit base values or [AppTypographyScale.standard.multiplier] here (or pass
/// another scale when building [ThemeData]) — widgets read sizes via
/// [TextTheme] / [AppTextStyles], not these constants directly.
///
/// Exceptions: terminal [TerminalStyle] uses [terminal]; see `chat_workbench.dart`.

/// Persisted scale ids (settings UI order).
const List<String> kTypographyScaleIds = [
  'compact',
  'standard',
  'comfortable',
  'custom',
];

const String kDefaultTypographyScaleId = 'standard';

/// Allowed custom multiplier (× standard).
const double kTypographyCustomMultiplierMin = 0.75;
const double kTypographyCustomMultiplierMax = 1.35;
const double kDefaultTypographyCustomMultiplier = 1.0;

String normalizeTypographyScale(String? raw) {
  if (raw != null && kTypographyScaleIds.contains(raw)) return raw;
  return kDefaultTypographyScaleId;
}

double clampTypographyCustomMultiplier(double value) =>
    value.clamp(kTypographyCustomMultiplierMin, kTypographyCustomMultiplierMax);

AppTypographyScale typographyScaleForId(String id) =>
    switch (normalizeTypographyScale(id)) {
      'compact' => AppTypographyScale.compact,
      'comfortable' => AppTypographyScale.comfortable,
      'custom' => AppTypographyScale(
        multiplier: kDefaultTypographyCustomMultiplier,
      ),
      _ => AppTypographyScale.standard,
    };

AppTypographyScale typographyScaleForPreferences({
  required String scaleId,
  required double customMultiplier,
}) {
  if (normalizeTypographyScale(scaleId) == 'custom') {
    return AppTypographyScale(
      multiplier: clampTypographyCustomMultiplier(customMultiplier),
    );
  }
  return typographyScaleForId(scaleId);
}

@immutable
final class AppTypographyScale {
  const AppTypographyScale({this.multiplier = 1.0});

  /// Default scale used by [buildLightTheme] / [buildDarkTheme].
  static const standard = AppTypographyScale();

  /// Slightly denser UI (≈ −8%).
  static const compact = AppTypographyScale(multiplier: 0.92);

  /// Slightly roomier UI (≈ +8%).
  static const comfortable = AppTypographyScale(multiplier: 1.08);

  /// Applied to every role below (also composes with [MediaQuery.textScaler]).
  final double multiplier;

  // --- Base sizes at multiplier 1.0 (Material 3 type scale) ---

  static const double titleLargeBase = 22;
  static const double titleMediumBase = 16;
  static const double titleSmallBase = 14;
  static const double bodyLargeBase = 16;
  static const double bodyMediumBase = 14;
  static const double bodySmallBase = 12;
  static const double labelMediumBase = 12;
  static const double labelSmallBase = 11;

  /// xterm / bundled terminal face (not [TextTheme]).
  static const double terminalBase = 14;
  static const double terminalMultiplier = 1.0;

  /// Code editor & log viewer monospace (defaults to body medium).
  static const double monoBase = bodyMediumBase;

  double get titleLarge => titleLargeBase * multiplier;
  double get titleMedium => titleMediumBase * multiplier;
  double get titleSmall => titleSmallBase * multiplier;
  double get bodyLarge => bodyLargeBase * multiplier;
  double get bodyMedium => bodyMediumBase * multiplier;
  double get bodySmall => bodySmallBase * multiplier;
  double get labelMedium => labelMediumBase * multiplier;
  double get labelSmall => labelSmallBase * multiplier;
  double get terminal => terminalBase * multiplier * terminalMultiplier;
  double get mono => monoBase * multiplier;
}

/// Resolved sizes on [ThemeData.extensions] (from [AppTypographyScale]).
@immutable
final class AppTypographyTheme extends ThemeExtension<AppTypographyTheme> {
  const AppTypographyTheme({
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelMedium,
    required this.labelSmall,
    required this.mono,
    required this.terminal,
  });

  final double titleLarge;
  final double titleMedium;
  final double titleSmall;
  final double bodyLarge;
  final double bodyMedium;
  final double bodySmall;
  final double labelMedium;
  final double labelSmall;
  final double mono;
  final double terminal;

  factory AppTypographyTheme.fromScale(AppTypographyScale scale) {
    return AppTypographyTheme(
      titleLarge: scale.titleLarge,
      titleMedium: scale.titleMedium,
      titleSmall: scale.titleSmall,
      bodyLarge: scale.bodyLarge,
      bodyMedium: scale.bodyMedium,
      bodySmall: scale.bodySmall,
      labelMedium: scale.labelMedium,
      labelSmall: scale.labelSmall,
      mono: scale.mono,
      terminal: scale.terminal,
    );
  }

  static AppTypographyTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppTypographyTheme>() ??
      AppTypographyTheme.fromScale(AppTypographyScale.standard);

  @override
  AppTypographyTheme copyWith({
    double? titleLarge,
    double? titleMedium,
    double? titleSmall,
    double? bodyLarge,
    double? bodyMedium,
    double? bodySmall,
    double? labelMedium,
    double? labelSmall,
    double? mono,
    double? terminal,
  }) {
    return AppTypographyTheme(
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      mono: mono ?? this.mono,
      terminal: terminal ?? this.terminal,
    );
  }

  @override
  AppTypographyTheme lerp(ThemeExtension<AppTypographyTheme>? other, double t) {
    if (other is! AppTypographyTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppTypographyThemeContext on BuildContext {
  AppTypographyTheme get appTypography => AppTypographyTheme.fromContext(this);
}
