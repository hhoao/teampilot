import 'package:flutter/material.dart';

/// VS Code-style colors for the compact find/replace bars (chat + editor).
///
/// Dark values mirror the `find-replace.html` mockup; light values mirror
/// VS Code's Light theme. Resolve with [FindBarPalette.of].
class FindBarPalette extends ThemeExtension<FindBarPalette> {
  const FindBarPalette({
    required this.panelBg,
    required this.panelBorder,
    required this.fieldBg,
    required this.border,
    required this.focusBorder,
    required this.text,
    required this.mutedText,
    required this.icon,
    required this.hoverBg,
    required this.activeBg,
    required this.activeBorder,
    required this.toggleOnText,
    required this.shadow,
  });

  /// Panel background.
  final Color panelBg;

  /// Outer hairline border of the panel.
  final Color panelBorder;

  /// Find/replace input field background.
  final Color fieldBg;

  /// Input field idle border.
  final Color border;

  /// Input field focus border (also the active accent color).
  final Color focusBorder;

  /// Primary text (counter).
  final Color text;

  /// Muted text (hints, "no results").
  final Color mutedText;

  /// Icon button glyph color.
  final Color icon;

  /// Hover fill for buttons and toggles.
  final Color hoverBg;

  /// Fill for an active (on) toggle.
  final Color activeBg;

  /// Border for an active (on) toggle.
  final Color activeBorder;

  /// Label color of an active (on) toggle.
  final Color toggleOnText;

  /// Panel drop-shadow color.
  final Color shadow;

  /// Dark theme (the `find-replace.html` mockup).
  static const FindBarPalette dark = FindBarPalette(
    panelBg: Color(0xFF252526),
    panelBorder: Color(0xFF454545),
    fieldBg: Color(0xFF3C3C3C),
    border: Color(0xFF3C3C3C),
    focusBorder: Color(0xFF007FD4),
    text: Color(0xFFCCCCCC),
    mutedText: Color(0xFF858585),
    icon: Color(0xFFC5C5C5),
    hoverBg: Color(0xFF2A2D2E),
    activeBg: Color(0xFF3A3D41),
    activeBorder: Color(0xFF007FD4),
    toggleOnText: Color(0xFFFFFFFF),
    shadow: Color(0x5C000000),
  );

  /// Light theme (VS Code Light equivalents).
  static const FindBarPalette light = FindBarPalette(
    panelBg: Color(0xFFF3F3F3),
    panelBorder: Color(0xFFC8C8C8),
    fieldBg: Color(0xFFFFFFFF),
    border: Color(0xFFC8C8C8),
    focusBorder: Color(0xFF006BB1),
    text: Color(0xFF333333),
    mutedText: Color(0xFF6B6B6B),
    icon: Color(0xFF424242),
    hoverBg: Color(0xFFE5EBF1),
    activeBg: Color(0xFFC9E5FF),
    activeBorder: Color(0xFF006BB1),
    toggleOnText: Color(0xFF006BB1),
    shadow: Color(0x26000000),
  );

  /// Resolves the palette for [context], falling back on [Brightness] when no
  /// extension is registered.
  static FindBarPalette of(BuildContext context) {
    final extension = Theme.of(context).extension<FindBarPalette>();
    if (extension != null) {
      return extension;
    }
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  FindBarPalette copyWith({
    Color? panelBg,
    Color? panelBorder,
    Color? fieldBg,
    Color? border,
    Color? focusBorder,
    Color? text,
    Color? mutedText,
    Color? icon,
    Color? hoverBg,
    Color? activeBg,
    Color? activeBorder,
    Color? toggleOnText,
    Color? shadow,
  }) {
    return FindBarPalette(
      panelBg: panelBg ?? this.panelBg,
      panelBorder: panelBorder ?? this.panelBorder,
      fieldBg: fieldBg ?? this.fieldBg,
      border: border ?? this.border,
      focusBorder: focusBorder ?? this.focusBorder,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      icon: icon ?? this.icon,
      hoverBg: hoverBg ?? this.hoverBg,
      activeBg: activeBg ?? this.activeBg,
      activeBorder: activeBorder ?? this.activeBorder,
      toggleOnText: toggleOnText ?? this.toggleOnText,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  FindBarPalette lerp(FindBarPalette? other, double t) {
    if (other == null) {
      return this;
    }
    return FindBarPalette(
      panelBg: Color.lerp(panelBg, other.panelBg, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      fieldBg: Color.lerp(fieldBg, other.fieldBg, t)!,
      border: Color.lerp(border, other.border, t)!,
      focusBorder: Color.lerp(focusBorder, other.focusBorder, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
      hoverBg: Color.lerp(hoverBg, other.hoverBg, t)!,
      activeBg: Color.lerp(activeBg, other.activeBg, t)!,
      activeBorder: Color.lerp(activeBorder, other.activeBorder, t)!,
      toggleOnText: Color.lerp(toggleOnText, other.toggleOnText, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
