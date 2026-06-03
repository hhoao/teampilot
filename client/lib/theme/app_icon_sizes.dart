import 'package:flutter/material.dart';

/// Central **icon pixel sizes** for TeamPilot UI.
///
/// [buildLightTheme] / [buildDarkTheme] set [IconThemeData.size] to [md].
/// **Default:** use [md] or omit `size` and rely on [IconTheme]. Other roles are
/// available when a screen needs denser chrome or larger illustrations.
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

  /// Default [IconThemeData] for app themes.
  static IconThemeData iconTheme({Color? color}) =>
      IconThemeData(size: md, color: color);
}

extension AppIconSizesContext on BuildContext {
  /// Resolved default icon size from [ThemeData.iconTheme].
  double get appIconSize => IconTheme.of(this).size ?? AppIconSizes.md;
}
