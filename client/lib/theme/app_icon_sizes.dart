import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

/// Central **icon sizes and colors** for TeamPilot UI.
///
/// [buildLightTheme] / [buildDarkTheme] set [IconThemeData] to [md] + [AppIconColors.icon].
/// **Default:** omit `size` / `color` on [Icon] and rely on [IconTheme]. For muted
/// or disabled glyphs use [AppIconColors.iconMuted] / [AppIconColors.iconDisabled].
/// Other size roles are available when a screen needs denser chrome or illustrations.
///
/// Baseline design tokens at multiplier 1.0. Widgets should read scaled sizes via
/// [BuildContext.appIconSizes] (from [AppIconSizeTheme], driven by
/// [resolveIconMultiplier] in [buildLightTheme] / [buildDarkTheme]).
abstract final class AppIconSizes {
  AppIconSizes._();

  // --- Baseline at multiplier 1.0 ---
  //
  // Tuned ~18% smaller than the original design values (md 22→18, etc.) so icons
  // sit closer to the 14px body text (ratio ~1.3 instead of ~1.57).

  /// Ultra-dense chrome (e.g. session tab overflow).
  static const double xxsBase = 14;

  /// Dense chrome (e.g. editor/terminal tab actions).
  static const double xsBase = 15;

  /// Compact list/toolbar glyph ([AppIconButton] compact preset).
  static const double smBase = 16;

  /// Default interactive icon: lists, toolbars, title bars, buttons.
  static const double mdBase = 18;

  /// Emphasized nav / search fields.
  static const double lgBase = 20;

  /// Dropdown suffix chevron.
  static const double xlBase = 22;

  /// Hub nav tile at [WorkspaceHubNavDensity.relaxed].
  static const double navRelaxedBase = 20;

  /// Inline list / card leading glyph.
  static const double listBase = 30;

  /// Empty-state illustration.
  static const double emptyBase = 34;

  /// Feature / settings hero icon.
  static const double heroBase = 38;

  /// Large empty / error states.
  static const double displayBase = 44;

  /// Global shrink on icon baselines (design tuning).
  static const double baselineScale = 1.32;

  /// Portion of the **user** text-size delta (compact / comfortable / custom,
  /// relative to the per-system auto baseline) applied to icon sizes. The OS
  /// auto text baseline is not passed through — see [resolveIconMultiplier].
  static const double userScaleTracking = 0.75;

  /// Maps effective text multiplier → icon multiplier.
  ///
  /// Text uses [effectiveTextMultiplier] (includes OS auto baseline on high-DPI).
  /// Icons keep a fixed baseline on screen and only pick up user preset changes,
  /// damped by [userScaleTracking] and [baselineScale].
  static double resolveIconMultiplier({
    required double effectiveTextMultiplier,
    required double textBaseline,
  }) {
    final baseline = textBaseline <= 0 ? 1.0 : textBaseline;
    final userRelative = effectiveTextMultiplier / baseline;
    final userMapped = 1.0 + (userRelative - 1.0) * userScaleTracking;
    return baselineScale * userMapped;
  }

  // --- Baseline aliases (multiplier 1.0; prefer [AppIconSizeTheme] in UI) ---

  static const double xxs = xxsBase;
  static const double xs = xsBase;
  static const double sm = smBase;
  static const double md = mdBase;
  static const double lg = lgBase;
  static const double xl = xlBase;
  static const double navRelaxed = navRelaxedBase;
  static const double list = listBase;
  static const double empty = emptyBase;
  static const double hero = heroBase;
  static const double display = displayBase;

  /// Default [IconThemeData] for app themes ([md] = [mdBase] × [scale].multiplier).
  static IconThemeData iconTheme(
    ColorScheme scheme, {
    AppTypographyScale scale = AppTypographyScale.standard,
  }) => IconThemeData(size: mdBase * scale.multiplier, color: scheme.icon);
}

/// Semantic icon colors aligned with [ThemeData.iconTheme].
extension AppIconColors on ColorScheme {
  /// Default interactive glyph ([ThemeData.iconTheme]).
  Color get icon => onSurface;

  /// Secondary / hint glyphs (search fields, placeholders).
  Color get iconMuted => onSurfaceVariant;

  /// Disabled toolbar and list icons (Material 3 disabled opacity).
  Color get iconDisabled => icon.withValues(alpha: 0.38);
}

extension AppIconSizesContext on BuildContext {
  /// Resolved default icon size from [ThemeData.iconTheme].
  double get appIconSize => IconTheme.of(this).size ?? AppIconSizes.md;

  /// Resolved default icon color from [ThemeData.iconTheme].
  Color get appIconColor =>
      IconTheme.of(this).color ?? Theme.of(this).colorScheme.icon;
}

/// Resolved icon sizes on [ThemeData.extensions], scaled by the active
/// [AppTypographyScale] multiplier. Read non-default roles via
/// [BuildContext.appIconSizes]; the default size also flows through
/// [ThemeData.iconTheme].
@immutable
final class AppIconSizeTheme extends ThemeExtension<AppIconSizeTheme> {
  const AppIconSizeTheme({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.navRelaxed,
    required this.list,
    required this.empty,
    required this.hero,
    required this.display,
  });

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double navRelaxed;
  final double list;
  final double empty;
  final double hero;
  final double display;

  factory AppIconSizeTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppIconSizeTheme(
      xxs: AppIconSizes.xxsBase * m,
      xs: AppIconSizes.xsBase * m,
      sm: AppIconSizes.smBase * m,
      md: AppIconSizes.mdBase * m,
      lg: AppIconSizes.lgBase * m,
      xl: AppIconSizes.xlBase * m,
      navRelaxed: AppIconSizes.navRelaxedBase * m,
      list: AppIconSizes.listBase * m,
      empty: AppIconSizes.emptyBase * m,
      hero: AppIconSizes.heroBase * m,
      display: AppIconSizes.displayBase * m,
    );
  }

  /// Baseline sizes at multiplier 1.0 (tests / fallback when no extension).
  factory AppIconSizeTheme.resolved() => const AppIconSizeTheme(
    xxs: AppIconSizes.xxs,
    xs: AppIconSizes.xs,
    sm: AppIconSizes.sm,
    md: AppIconSizes.md,
    lg: AppIconSizes.lg,
    xl: AppIconSizes.xl,
    navRelaxed: AppIconSizes.navRelaxed,
    list: AppIconSizes.list,
    empty: AppIconSizes.empty,
    hero: AppIconSizes.hero,
    display: AppIconSizes.display,
  );

  static AppIconSizeTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppIconSizeTheme>() ??
      AppIconSizeTheme.fromScale(AppTypographyScale.standard);

  @override
  AppIconSizeTheme copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? navRelaxed,
    double? list,
    double? empty,
    double? hero,
    double? display,
  }) => AppIconSizeTheme(
    xxs: xxs ?? this.xxs,
    xs: xs ?? this.xs,
    sm: sm ?? this.sm,
    md: md ?? this.md,
    lg: lg ?? this.lg,
    xl: xl ?? this.xl,
    navRelaxed: navRelaxed ?? this.navRelaxed,
    list: list ?? this.list,
    empty: empty ?? this.empty,
    hero: hero ?? this.hero,
    display: display ?? this.display,
  );

  @override
  AppIconSizeTheme lerp(ThemeExtension<AppIconSizeTheme>? other, double t) {
    if (other is! AppIconSizeTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppIconSizeThemeContext on BuildContext {
  AppIconSizeTheme get appIconSizes => AppIconSizeTheme.fromContext(this);
}
