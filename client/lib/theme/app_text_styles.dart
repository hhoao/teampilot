import 'package:flutter/material.dart';

import 'app_fonts.dart';

enum _TextSize { xs, sm, md, lg, xl, display }

enum _TextWeight { normal, medium, semibold, bold }

enum _TextSpacing { tight, normal, track, spread, wide }

enum _TextHeight { snug, normal, relaxed }

/// Scale-based text styles backed by [ThemeData.textTheme] (sizes from
/// [AppTypographyScale] via [materializeM3TextThemeSizes]; also scales with
/// [MediaQuery.textScaler]). Do not set [TextStyle.fontSize] in widgets.
final class AppTextStyles {
  AppTextStyles(this.theme);

  final ThemeData theme;

  static AppTextStyles of(BuildContext context) =>
      AppTextStyles(Theme.of(context));

  TextTheme get _t => theme.textTheme;
  ColorScheme get _cs => theme.colorScheme;

  TextStyle _compose({
    required _TextSize size,
    _TextWeight weight = _TextWeight.normal,
    _TextSpacing spacing = _TextSpacing.normal,
    _TextHeight height = _TextHeight.normal,
  }) {
    final base = switch (size) {
      _TextSize.xs => _t.labelSmall,
      _TextSize.sm => _t.bodySmall,
      _TextSize.md => _t.bodyMedium,
      _TextSize.lg => _t.bodyLarge,
      _TextSize.xl => _t.titleLarge,
      _TextSize.display => _t.headlineSmall,
    };
    final resolvedHeight = switch (height) {
      _TextHeight.snug => 1.25,
      _TextHeight.normal => 1.35,
      _TextHeight.relaxed => 1.45,
    };
    final letterSpacing = switch (spacing) {
      _TextSpacing.tight => -0.15,
      _TextSpacing.normal => null,
      _TextSpacing.track => 0.2,
      _TextSpacing.spread => 0.4,
      _TextSpacing.wide => 0.8,
    };
    final fontWeight = switch (weight) {
      _TextWeight.normal => null,
      _TextWeight.medium => FontWeight.w500,
      _TextWeight.semibold => FontWeight.w600,
      _TextWeight.bold => FontWeight.w700,
    };
    var style = (base ?? const TextStyle()).copyWith(height: resolvedHeight);
    if (fontWeight != null) {
      style = style.copyWith(fontWeight: fontWeight);
    }
    if (letterSpacing != null) {
      style = style.copyWith(letterSpacing: letterSpacing);
    }
    return style;
  }

  TextStyle get xs => _compose(size: _TextSize.xs);

  TextStyle xsColored(Color color) => xs.copyWith(color: color);

  TextStyle get xsSemiboldSnug => _compose(
    size: _TextSize.xs,
    weight: _TextWeight.semibold,
    height: _TextHeight.snug,
  );

  TextStyle xsSemiboldSnugColored(Color color) =>
      xsSemiboldSnug.copyWith(color: color);

  TextStyle get xsBoldWide => _compose(
    size: _TextSize.xs,
    weight: _TextWeight.bold,
    spacing: _TextSpacing.wide,
  );

  TextStyle xsBoldWideColored(Color color) =>
      xsBoldWide.copyWith(color: color);

  TextStyle get xsTrack => _compose(
    size: _TextSize.xs,
    spacing: _TextSpacing.track,
  );

  TextStyle xsTrackColored(Color color) => xsTrack.copyWith(color: color);

  TextStyle get sm => _compose(size: _TextSize.sm);

  TextStyle smColored(Color color) => sm.copyWith(color: color);

  TextStyle get md => _compose(size: _TextSize.md);

  TextStyle mdColored(Color color) => md.copyWith(color: color);

  TextStyle get mdSnug => _compose(
    size: _TextSize.md,
    height: _TextHeight.snug,
  );

  TextStyle mdSnugColored(Color color) => mdSnug.copyWith(color: color);

  TextStyle get mdMedium => _compose(
    size: _TextSize.md,
    weight: _TextWeight.medium,
  );

  TextStyle mdMediumColored(Color color) => mdMedium.copyWith(color: color);

  TextStyle get mdSemibold => _compose(
    size: _TextSize.md,
    weight: _TextWeight.semibold,
  );

  TextStyle mdSemiboldColored(Color color) =>
      mdSemibold.copyWith(color: color);

  TextStyle get mdSemiboldTightSnug => _compose(
    size: _TextSize.md,
    weight: _TextWeight.semibold,
    spacing: _TextSpacing.tight,
    height: _TextHeight.snug,
  );

  TextStyle mdSemiboldTightSnugColored(Color color) =>
      mdSemiboldTightSnug.copyWith(color: color);

  TextStyle get mdBoldSpread => _compose(
    size: _TextSize.md,
    weight: _TextWeight.bold,
    spacing: _TextSpacing.spread,
  );

  TextStyle mdBoldSpreadColored(Color color) =>
      mdBoldSpread.copyWith(color: color);

  TextStyle get lg => _compose(size: _TextSize.lg);

  TextStyle lgColored(Color color) => lg.copyWith(color: color);

  TextStyle get lgSnug => _compose(
    size: _TextSize.lg,
    height: _TextHeight.snug,
  );

  TextStyle lgSnugColored(Color color) => lgSnug.copyWith(color: color);

  TextStyle get lgSemiboldSnug => _compose(
    size: _TextSize.lg,
    weight: _TextWeight.semibold,
    height: _TextHeight.snug,
  );

  TextStyle lgSemiboldSnugColored(Color color) =>
      lgSemiboldSnug.copyWith(color: color);

  TextStyle get xl => _compose(size: _TextSize.xl);

  TextStyle xlColored(Color color) => xl.copyWith(color: color);

  TextStyle get display => _compose(size: _TextSize.display);

  TextStyle displayColored(Color color) => display.copyWith(color: color);

  TextStyle get mutedXs =>
      xs.copyWith(color: _cs.onSurfaceVariant);

  TextStyle get mutedSm =>
      sm.copyWith(color: _cs.onSurfaceVariant);

  TextStyle get mutedMd =>
      md.copyWith(color: _cs.onSurfaceVariant);

  /// Monospace body (terminal / JSON); family from [AppFontTheme].
  TextStyle get mono {
    final fonts = theme.extension<AppFontTheme>() ?? AppFontTheme.fallback;
    return _compose(size: _TextSize.md).copyWith(
      fontFamily: fonts.monoFontFamily,
      fontFamilyFallback: fonts.monoFontFamilyFallback,
    );
  }

  TextStyle monoColored(Color color) => mono.copyWith(color: color);
}

/// Dropdown / form field text: [TextTheme.bodyMedium] with optional weight.
TextStyle dropdownFieldTextStyle(
  BuildContext context, {
  Color? color,
  FontWeight? fontWeight,
  bool enabled = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  final resolvedColor =
      color ??
      (enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.5));
  return base.copyWith(
    fontWeight: fontWeight ?? FontWeight.w500,
    color: resolvedColor,
    height: 1.25,
  );
}

TextStyle dropdownHintTextStyle(BuildContext context, {bool enabled = true}) {
  final scheme = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  final alpha = enabled ? 0.45 : 0.35;
  return base.copyWith(
    color: scheme.onSurface.withValues(alpha: alpha),
    fontWeight: FontWeight.w400,
    height: 1.25,
  );
}
