import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Central **font size** configuration for TeamPilot UI.
///
/// Edit base values or [AppTypographyScale.standard.multiplier] here (or pass
/// another scale when building [ThemeData]) — widgets read sizes via
/// [TextTheme] / [TpTextStyles], not these constants directly.
///
/// Exceptions: terminal [TerminalStyle] uses [terminal]; see `chat_workbench.dart`.

/// Persisted scale ids (settings UI order). These are **relative** levels: the
/// effective scale is `autoBaseline × thisMultiplier`, where the baseline is the
/// per-system auto value (text: [autoTextScaleForSystem]; zoom:
/// [autoUiZoomForDevicePixelRatio]). So `standard` (×1.0) == auto, `compact` is
/// a bit tighter, `comfortable` a bit looser, `custom` a % of standard.
const List<String> kTypographyScaleIds = [
  'compact',
  'standard',
  'comfortable',
  'custom',
];

const String kDefaultTypographyScaleId = 'standard';

/// Allowed custom **text-size** multiplier (× standard). Max is generous so the
/// in-app text size can replicate large OS text-scaling (e.g. GNOME 1.5).
const double kTypographyCustomMultiplierMin = 0.5;
const double kTypographyCustomMultiplierMax = 2.0;
const double kDefaultTypographyCustomMultiplier = 1.0;

/// Final-effective **interface zoom** clamp (whole-UI [UiZoom]).
const double kUiZoomMin = 0.5;
const double kUiZoomMax = 1.5;

double clampUiZoom(double value) => value.clamp(kUiZoomMin, kUiZoomMax);

/// Fixed step applied per press by the `workbench.zoom.in`/`.out` commands.
const double kUiZoomStep = 0.1;

/// Clamps a `uiZoomCustomMultiplier` candidate so the *effective* zoom
/// (`baseline × multiplier`, i.e. what [UiZoom] actually renders) stays
/// within [kUiZoomMin]/[kUiZoomMax], expressed back in multiplier space so
/// the stored preference stays baseline-independent. Callers without a
/// device [baseline] (e.g. tests, or code that hasn't resolved
/// [autoUiZoomForDevicePixelRatio] yet) may pass the default `1.0`.
double clampUiZoomMultiplierForBaseline(
  double multiplier, {
  double baseline = 1.0,
}) {
  if (baseline <= 0) return multiplier.clamp(kUiZoomMin, kUiZoomMax);
  return clampUiZoom(baseline * multiplier) / baseline;
}

/// `standard` whole-UI zoom baseline for a display [devicePixelRatio]. The
/// `standard` preset maps to this; compact/comfortable/custom are relative to
/// it.
///
/// When [compensateDisplayScaling] is true and macOS ([useMacOSBaselines] or
/// runtime probe), returns `(1 / dpr) ×` [kMacUiZoomBaseline] (126% of the
/// Linux/Windows auto baseline).
///
/// Other desktops undo OS display scaling via `1/dpr`: Windows @150% (dpr 1.5)
/// → ~0.67, Linux @100% (dpr 1.0) → 1.0.
///
/// When false (Android/iOS), returns [kMobileUiZoomBaseline]: logical pixels
/// already absorb dpr; mobile `standard` zoom is denser than desktop 1.0.
double autoUiZoomForDevicePixelRatio(
  double devicePixelRatio, {
  bool compensateDisplayScaling = true,
  bool? useMacOSBaselines,
}) {
  if (!compensateDisplayScaling) return kMobileUiZoomBaseline;
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  if (_resolveMacOSBaselines(useMacOSBaselines)) {
    return kMacUiZoomBaseline / dpr;
  }
  return 1.0 / dpr;
}

String normalizeTypographyScale(String? raw) {
  if (raw != null && kTypographyScaleIds.contains(raw)) return raw;
  return kDefaultTypographyScaleId;
}

double clampTypographyCustomMultiplier(double value) =>
    value.clamp(kTypographyCustomMultiplierMin, kTypographyCustomMultiplierMax);

/// Mobile `standard` text-size baseline (× OS accessibility text scale).
/// Logical pixels already absorb dpr; 1.3 lifts touch readability vs desktop.
const double kMobileTextScaleBaseline = 1.3;

/// Mobile `standard` interface-zoom baseline. `standard` preset × 1.0 maps here.
const double kMobileUiZoomBaseline = 0.7;

/// macOS `standard` text-size baseline (72% × OS accessibility text scale).
const double kMacTextScaleBaseline = 0.72;

/// macOS `standard` interface-zoom baseline (126%).
const double kMacUiZoomBaseline = 1.26;

bool _resolveMacOSBaselines(bool? useMacOSBaselines) =>
    useMacOSBaselines ?? (!kIsWeb && Platform.isMacOS);

/// `standard` text-size baseline.
///
/// macOS ([useMacOSBaselines] or runtime probe): [osTextScale] × dpr ×
/// [kMacTextScaleBaseline] (72% of the Linux/Windows auto baseline). Combined
/// with interface zoom `(1/dpr) ×` [kMacUiZoomBaseline], on-screen text size
/// is dpr-independent (same cancellation as other desktops).
///
/// Other desktops ([compensateDisplayScaling] true): [osTextScale] (e.g. GNOME
/// text-scaling-factor) × [devicePixelRatio]. Combined with interface zoom
/// `1/dpr` this renders text at the size the OS would while icons/spacing stay
/// compact. e.g. Ubuntu GNOME 1.5 @100% → 1.5; Windows @150% → 1.5.
///
/// Mobile ([compensateDisplayScaling] false): [osTextScale] ×
/// [kMobileTextScaleBaseline]. Logical pixels already absorb dpr.
double autoTextScaleForSystem(
  double osTextScale,
  double devicePixelRatio, {
  bool compensateDisplayScaling = true,
  bool? useMacOSBaselines,
}) {
  final os = osTextScale <= 0 ? 1.0 : osTextScale;
  if (!compensateDisplayScaling) {
    return clampTypographyCustomMultiplier(os * kMobileTextScaleBaseline);
  }
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  if (_resolveMacOSBaselines(useMacOSBaselines)) {
    return clampTypographyCustomMultiplier(os * dpr * kMacTextScaleBaseline);
  }
  return clampTypographyCustomMultiplier(os * dpr);
}

/// Effective scale = [baseline] × the relative preset multiplier (compact 0.92,
/// standard 1.0, comfortable 1.08, or [customMultiplier] for `custom`). So
/// `standard` resolves to the auto baseline and the rest are relative to it.
double resolveRelativeScale({
  required String scaleId,
  required double customMultiplier,
  required double baseline,
}) =>
    baseline *
    typographyScaleForPreferences(
      scaleId: scaleId,
      customMultiplier: customMultiplier,
    ).multiplier;

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

  static const double headlineSmallBase = 24;
  static const double titleLargeBase = 20;
  static const double titleMediumBase = 16;
  static const double titleSmallBase = 14;
  static const double bodyLargeBase = 16;
  static const double bodyMediumBase = 14;
  static const double bodySmallBase = 12;

  /// Button labels ([TextButton]/[OutlinedButton]/[FilledButton] use M3
  /// `labelLarge`).
  static const double labelLargeBase = 14;
  static const double labelMediumBase = 12;
  static const double labelSmallBase = 11;

  /// xterm / bundled terminal face (not [TextTheme]).
  static const double terminalBase = 14;
  static const double terminalMultiplier = 1.0;

  /// Code editor & log viewer monospace (defaults to body medium).
  static const double monoBase = bodyMediumBase;

  double get headlineSmall => headlineSmallBase * multiplier;
  double get titleLarge => titleLargeBase * multiplier;
  double get titleMedium => titleMediumBase * multiplier;
  double get titleSmall => titleSmallBase * multiplier;
  double get bodyLarge => bodyLargeBase * multiplier;
  double get bodyMedium => bodyMediumBase * multiplier;
  double get bodySmall => bodySmallBase * multiplier;
  double get labelLarge => labelLargeBase * multiplier;
  double get labelMedium => labelMediumBase * multiplier;
  double get labelSmall => labelSmallBase * multiplier;
  double get terminal => terminalBase * multiplier * terminalMultiplier;
  double get mono => monoBase * multiplier;
}

/// Resolved sizes on [ThemeData.extensions] (from [AppTypographyScale]).
@immutable
final class AppTypographyTheme extends ThemeExtension<AppTypographyTheme> {
  const AppTypographyTheme({
    required this.headlineSmall,
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

  final double headlineSmall;
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
      headlineSmall: scale.headlineSmall,
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
    double? headlineSmall,
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
      headlineSmall: headlineSmall ?? this.headlineSmall,
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
