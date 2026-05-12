import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_workspace_settings_theme.dart';
import 'custom_dropdown.dart';

/// Themed [CustomDropdownDecoration] presets for FlashskyAI surfaces.
abstract final class FlashskyDropdownDecorations {
  static CustomDropdownDecoration settingsCompact(BuildContext context) {
    final colors = AppColors.of(context);
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final selectedBg = isDark
        ? colors.accentBlue.withValues(alpha: 0.2)
        : colors.selectedBackground;

    return CustomDropdownDecoration(
      closedFillColor: colors.inputFill,
      expandedFillColor: colors.rightPanelBackground,
      closedBorder: Border.all(color: colors.border),
      closedBorderRadius: BorderRadius.circular(tokens.dropdownBorderRadius),
      expandedBorder: Border.all(color: colors.subtleBorder),
      expandedBorderRadius: BorderRadius.circular(tokens.dropdownBorderRadius),
      expandedShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.1),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
      headerStyle: TextStyle(
        fontSize: tokens.dropdownLabelFontSize,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      hintStyle: TextStyle(
        fontSize: tokens.dropdownLabelFontSize,
        color: onSurface.withValues(alpha: 0.45),
      ),
      listItemStyle: TextStyle(
        fontSize: tokens.dropdownLabelFontSize,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      closedSuffixIcon: Icon(
        Icons.expand_more_rounded,
        size: 22,
        color: onSurface.withValues(alpha: tokens.dropdownIconOpacity),
      ),
      expandedSuffixIcon: Icon(
        Icons.expand_less_rounded,
        size: 22,
        color: onSurface.withValues(alpha: tokens.dropdownIconOpacity),
      ),
      listItemDecoration: ListItemDecoration(
        highlightColor: highlight,
        selectedColor: selectedBg,
        splashColor: Colors.transparent,
      ),
    );
  }

  static CustomDropdownDecoration sidebarTeam(BuildContext context) {
    final colors = AppColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final selectedBg = isDark
        ? colors.accentBlue.withValues(alpha: 0.22)
        : colors.selectedBackground;

    return CustomDropdownDecoration(
      closedFillColor: colors.teamSelectorBackground,
      expandedFillColor: colors.cardBackground,
      closedBorder: Border.all(color: colors.teamSelectorBorder),
      closedBorderRadius: BorderRadius.circular(8),
      expandedBorder: Border.all(color: colors.subtleBorder),
      expandedBorderRadius: BorderRadius.circular(8),
      expandedShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
      headerStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        color: onSurface.withValues(alpha: 0.45),
      ),
      listItemStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      closedSuffixIcon: Icon(
        Icons.expand_more_rounded,
        size: 18,
        color: onSurface.withValues(alpha: 0.55),
      ),
      expandedSuffixIcon: Icon(
        Icons.expand_less_rounded,
        size: 18,
        color: onSurface.withValues(alpha: 0.55),
      ),
      listItemDecoration: ListItemDecoration(
        highlightColor: highlight,
        selectedColor: selectedBg,
        splashColor: Colors.transparent,
      ),
    );
  }

  /// Dense fields (forms, dialogs, toolbar filters).
  static CustomDropdownDecoration denseField(
    BuildContext context, {
    double borderRadius = 8,
  }) {
    final colors = AppColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final selectedBg = isDark
        ? colors.accentBlue.withValues(alpha: 0.2)
        : colors.selectedBackground;

    return CustomDropdownDecoration(
      closedFillColor: colors.inputFill,
      expandedFillColor: colors.cardBackground,
      closedBorder: Border.all(color: colors.border),
      closedBorderRadius: BorderRadius.circular(borderRadius),
      expandedBorder: Border.all(color: colors.subtleBorder),
      expandedBorderRadius: BorderRadius.circular(borderRadius),
      expandedShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.1),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
      headerStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      hintStyle: TextStyle(
        fontSize: 14,
        color: onSurface.withValues(alpha: 0.45),
      ),
      listItemStyle: TextStyle(fontSize: 14, color: onSurface),
      closedSuffixIcon: Icon(
        Icons.expand_more_rounded,
        size: 20,
        color: onSurface.withValues(alpha: 0.55),
      ),
      expandedSuffixIcon: Icon(
        Icons.expand_less_rounded,
        size: 20,
        color: onSurface.withValues(alpha: 0.55),
      ),
      listItemDecoration: ListItemDecoration(
        highlightColor: highlight,
        selectedColor: selectedBg,
        splashColor: Colors.transparent,
      ),
    );
  }
}
