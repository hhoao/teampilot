import 'package:flutter/material.dart';

import 'app_fonts.dart';

/// Semantic text styles backed by [ThemeData.textTheme] (sizes from
/// [AppTypographyScale] via [materializeM3TextThemeSizes]; also scales with
/// [MediaQuery.textScaler]). Do not set [TextStyle.fontSize] in widgets.
final class AppTextStyles {
  AppTextStyles(this.theme);

  final ThemeData theme;

  static AppTextStyles of(BuildContext context) =>
      AppTextStyles(Theme.of(context));

  TextTheme get _t => theme.textTheme;
  ColorScheme get _cs => theme.colorScheme;

  TextStyle _resolve(TextStyle? style, {double height = 1.35}) =>
      (style ?? const TextStyle()).copyWith(height: height);

  /// 11px — badges, timestamps, tertiary line.
  TextStyle get caption => _resolve(_t.labelSmall);

  TextStyle captionColored(Color color, {FontWeight? fontWeight}) =>
      caption.copyWith(color: color, fontWeight: fontWeight);

  /// 12px — compact lists, tree nodes.
  TextStyle get bodySmall => _resolve(_t.bodySmall);

  TextStyle bodySmallColored(Color color, {FontWeight? fontWeight}) =>
      bodySmall.copyWith(color: color, fontWeight: fontWeight);

  /// 14px — body, hints, dropdown field text.
  TextStyle get body => _resolve(_t.bodyMedium);

  TextStyle bodyColored(Color color, {FontWeight? fontWeight}) =>
      body.copyWith(color: color, fontWeight: fontWeight);

  /// 14px semibold — row titles, primary list names.
  TextStyle get bodyStrong =>
      body.copyWith(fontWeight: FontWeight.w600, height: 1.25);

  TextStyle bodyStrongColored(Color color) => bodyStrong.copyWith(color: color);

  /// 16px — rare emphasis (not inputs/dropdowns).
  TextStyle get prominent => _resolve(_t.bodyLarge, height: 1.35);

  /// 14px semibold — section / card headers (replaces 15/18 literals).
  TextStyle get sectionTitle {
    final base = _t.titleSmall ?? _t.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.15,
      height: 1.25,
    );
  }

  TextStyle sectionTitleColored(Color color) =>
      sectionTitle.copyWith(color: color);

  /// 16px — in-page subtitles.
  TextStyle get subtitle => _resolve(_t.titleMedium, height: 1.25);

  /// 16px semibold — dialog titles ([AlertDialog] theme uses the same scale).
  TextStyle get dialogTitle =>
      _resolve(_t.titleMedium, height: 1.25).copyWith(fontWeight: FontWeight.w600);

  TextStyle get mutedBody => body.copyWith(color: _cs.onSurfaceVariant);

  TextStyle get mutedCaption => caption.copyWith(color: _cs.onSurfaceVariant);

  TextStyle get mutedBodySmall =>
      bodySmall.copyWith(color: _cs.onSurfaceVariant);

  /// Monospace body (terminal / JSON); family from [AppFontTheme].
  TextStyle get mono {
    final fonts = theme.extension<AppFontTheme>() ?? AppFontTheme.fallback;
    return (_t.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: fonts.monoFontFamily,
      fontFamilyFallback: fonts.monoFontFamilyFallback,
      height: 1.35,
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
