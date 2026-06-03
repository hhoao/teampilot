import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// Themed dropdown chrome for [FlashskyDropdownField] (AppFlowy popover style).
class AppDropdownDecoration {
  const AppDropdownDecoration({
    required this.closedFillColor,
    required this.expandedFillColor,
    required this.closedBorder,
    required this.expandedBorder,
    required this.closedBorderRadius,
    required this.expandedBorderRadius,
    required this.expandedShadow,
    required this.headerStyle,
    required this.hintStyle,
    required this.listItemStyle,
    required this.closedSuffixIcon,
    required this.expandedSuffixIcon,
    required this.suffixIconSize,
    required this.listItemHighlightColor,
    required this.listItemSelectedColor,
    this.menuPadding = const EdgeInsets.fromLTRB(8, 12, 8, 12),
    this.menuFillColor,
    this.menuBorder,
    this.menuBorderRadius,
    this.buttonHoverColor,
    this.listItemBorderRadius,
  });

  final Color closedFillColor;
  final Color expandedFillColor;
  final BoxBorder closedBorder;
  final BoxBorder expandedBorder;
  final BorderRadius closedBorderRadius;
  final BorderRadius expandedBorderRadius;
  final List<BoxShadow> expandedShadow;
  final TextStyle? headerStyle;
  final TextStyle? hintStyle;
  final TextStyle? listItemStyle;
  final Widget closedSuffixIcon;
  final Widget expandedSuffixIcon;
  final double suffixIconSize;
  final Color listItemHighlightColor;
  final Color listItemSelectedColor;
  final EdgeInsetsGeometry menuPadding;
  final Color? menuFillColor;
  final BoxBorder? menuBorder;
  final BorderRadius? menuBorderRadius;
  final Color? buttonHoverColor;
  final BorderRadius? listItemBorderRadius;

  BoxDecoration buttonDecoration({
    required bool menuOpen,
    bool isHovering = false,
  }) {
    Color fill = menuOpen ? expandedFillColor : closedFillColor;
    if (!menuOpen && isHovering && buttonHoverColor != null) {
      fill = buttonHoverColor!;
    }
    return BoxDecoration(
      color: fill,
      border: menuOpen ? expandedBorder : closedBorder,
      borderRadius: menuOpen ? expandedBorderRadius : closedBorderRadius,
    );
  }

  BoxDecoration menuDecoration() {
    return BoxDecoration(
      color: menuFillColor ?? expandedFillColor,
      border: menuBorder ?? expandedBorder,
      borderRadius: menuBorderRadius ?? expandedBorderRadius,
      boxShadow: expandedShadow,
    );
  }
}

/// Back-compat alias; prefer [AppDropdownDecoration].
typedef CustomDropdownDecoration = AppDropdownDecoration;

/// Themed [AppDropdownDecoration] presets for TeamPilot surfaces.
abstract final class AppDropdownDecorations {
  /// Themed dropdown: outlined trigger, card menu with border/shadow.
  static AppDropdownDecoration themed(
    BuildContext context, {
    Color? closedFillColor,
    Color? expandedFillColor,
    BoxBorder? closedBorder,
    BoxBorder? expandedBorder,
    double borderRadius = 6,
    Color? buttonHoverColor,
    Color? menuFillColor,
    BoxBorder? menuBorder,
    double menuBorderRadius = 10,
    List<BoxShadow>? expandedShadow,
    double expandedShadowBlurRadius = 20,
    Offset expandedShadowOffset = const Offset(0, 4),
    double expandedShadowAlphaDark = 0.48,
    double expandedShadowAlphaLight = 0.10,
    TextStyle? headerStyle,
    TextStyle? hintStyle,
    TextStyle? listItemStyle,
    FontWeight headerFontWeight = FontWeight.w600,
    FontWeight? listItemFontWeight = FontWeight.w500,
    Widget? closedSuffixIcon,
    Widget? expandedSuffixIcon,
    double suffixIconSize = AppIconSizes.md,
    double suffixIconOpacity = 0.55,
    double highlightAlphaDark = 0.06,
    double highlightAlphaLight = 0.04,
    double selectedPrimaryAlphaDark = 0.2,
    double listItemBorderRadius = 6,
    EdgeInsetsGeometry? menuPadding,
  }) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.04);

    final highlight = isDark
        ? Colors.white.withValues(alpha: highlightAlphaDark)
        : Colors.black.withValues(alpha: highlightAlphaLight);
    final selectedBg = isDark
        ? cs.primary.withValues(alpha: selectedPrimaryAlphaDark)
        : cs.primaryContainer;

    final buttonRadius = BorderRadius.circular(borderRadius);
    final outlineVariant = cs.outlineVariant;

    return AppDropdownDecoration(
      closedFillColor: closedFillColor ?? Colors.transparent,
      expandedFillColor: expandedFillColor ?? hoverBg,
      closedBorder:
          closedBorder ?? Border.all(color: outlineVariant, width: 1),
      expandedBorder:
          expandedBorder ?? Border.all(color: cs.primary, width: 1),
      closedBorderRadius: buttonRadius,
      expandedBorderRadius: buttonRadius,
      buttonHoverColor: buttonHoverColor ?? hoverBg,
      menuFillColor: menuFillColor ?? cs.workspaceCard,
      menuBorder: menuBorder ?? Border.all(color: outlineVariant),
      menuBorderRadius: BorderRadius.circular(menuBorderRadius),
      expandedShadow: expandedShadow ??
          [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isDark
                    ? expandedShadowAlphaDark
                    : expandedShadowAlphaLight,
              ),
              blurRadius: expandedShadowBlurRadius,
              offset: expandedShadowOffset,
            ),
          ],
      headerStyle: headerStyle ??
          dropdownFieldTextStyle(
            context,
            color: onSurface,
            fontWeight: headerFontWeight,
          ),
      hintStyle: hintStyle ?? dropdownHintTextStyle(context),
      listItemStyle: listItemStyle ??
          dropdownFieldTextStyle(
            context,
            color: onSurface,
            fontWeight: listItemFontWeight,
          ),
      closedSuffixIcon: closedSuffixIcon ??
          _suffixIcon(
            Icons.expand_more_rounded,
            onSurface,
            suffixIconSize,
            suffixIconOpacity,
          ),
      expandedSuffixIcon: expandedSuffixIcon ??
          _suffixIcon(
            Icons.expand_less_rounded,
            onSurface,
            suffixIconSize,
            suffixIconOpacity,
          ),
      suffixIconSize: suffixIconSize,
      listItemHighlightColor: highlight,
      listItemSelectedColor: selectedBg,
      listItemBorderRadius: BorderRadius.circular(listItemBorderRadius),
      menuPadding: menuPadding ?? const EdgeInsets.fromLTRB(8, 12, 8, 12),
    );
  }

  static Widget _suffixIcon(
    IconData icon,
    Color onSurface,
    double size,
    double opacity,
  ) {
    return Icon(
      icon,
      size: size,
      color: onSurface.withValues(alpha: opacity),
    );
  }
}
