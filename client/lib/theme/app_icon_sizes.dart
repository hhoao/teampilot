import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

/// Central **icon sizes and colors** for TeamPilot UI.
///
/// [buildLightTheme] / [buildDarkTheme] set [IconThemeData] to [md] + [AppIconColors.icon].
/// **Default:** omit `size` / `color` on [Icon] and rely on [IconTheme]. For muted
/// or disabled glyphs use [AppIconColors.iconMuted] / [AppIconColors.iconDisabled].
/// Other size roles are available when a screen needs denser chrome or illustrations.
///
/// All roles scale with [multiplier] (same pattern as [AppTypographyScale]).
abstract final class AppIconSizes {
  AppIconSizes._();

  /// Global scale factor (1.0 = design baseline below).
  static const double multiplier = 1.0;

  // --- Baseline at multiplier 1.0 ---

  /// Ultra-dense chrome (e.g. session tab overflow).
  static const double xxsBase = 16;

  /// Dense chrome (e.g. editor/terminal tab actions).
  static const double xsBase = 18;

  /// Compact list/toolbar glyph ([AppIconButton] compact preset).
  static const double smBase = 20;

  /// Default interactive icon: lists, toolbars, title bars, buttons.
  static const double mdBase = 22;

  /// Emphasized nav / search fields.
  static const double lgBase = 24;

  /// Dropdown suffix chevron.
  static const double xlBase = 26;

  /// Hub nav tile at [WorkspaceHubNavDensity.relaxed].
  static const double navRelaxedBase = 25;

  /// Inline list / card leading glyph.
  static const double listBase = 36;

  /// Empty-state illustration.
  static const double emptyBase = 40;

  /// Feature / settings hero icon.
  static const double heroBase = 44;

  /// Large empty / error states.
  static const double displayBase = 52;

  // --- Resolved sizes (const while [multiplier] is 1.0) ---

  static const double xxs = xxsBase * multiplier;
  static const double xs = xsBase * multiplier;
  static const double sm = smBase * multiplier;
  static const double md = mdBase * multiplier;
  static const double lg = lgBase * multiplier;
  static const double xl = xlBase * multiplier;
  static const double navRelaxed = navRelaxedBase * multiplier;
  static const double list = listBase * multiplier;
  static const double empty = emptyBase * multiplier;
  static const double hero = heroBase * multiplier;
  static const double display = displayBase * multiplier;

  /// Default [IconThemeData] for app themes, scaled by [multiplier].
  static IconThemeData iconTheme(ColorScheme scheme, {double multiplier = 1.0}) =>
      IconThemeData(size: mdBase * multiplier, color: scheme.icon);
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
