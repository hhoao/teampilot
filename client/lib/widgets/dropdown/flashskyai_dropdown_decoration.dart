import 'package:flutter/material.dart';

import 'custom_dropdown.dart';

const _dropdownBorderRadius = 10.0;
const _dropdownIconOpacity = 0.55;
const _dropdownLabelFontSize = 13.0;

/// Themed [CustomDropdownDecoration] presets for FlashskyAI surfaces.
abstract final class FlashskyDropdownDecorations {
  static CustomDropdownDecoration settingsCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final selectedBg = isDark
        ? cs.primary.withValues(alpha: 0.2)
        : cs.primaryContainer;

    return CustomDropdownDecoration(
      closedFillColor: cs.surfaceContainerHigh,
      expandedFillColor: cs.surfaceContainerLow,
      closedBorder: Border.all(color: cs.outlineVariant),
      closedBorderRadius: BorderRadius.circular(_dropdownBorderRadius),
      expandedBorder: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.5),
      ),
      expandedBorderRadius: BorderRadius.circular(_dropdownBorderRadius),
      expandedShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.1),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
      headerStyle: TextStyle(
        fontSize: _dropdownLabelFontSize,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      hintStyle: TextStyle(
        fontSize: _dropdownLabelFontSize,
        color: onSurface.withValues(alpha: 0.45),
      ),
      listItemStyle: TextStyle(
        fontSize: _dropdownLabelFontSize,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      closedSuffixIcon: Icon(
        Icons.expand_more_rounded,
        size: 22,
        color: onSurface.withValues(alpha: _dropdownIconOpacity),
      ),
      expandedSuffixIcon: Icon(
        Icons.expand_less_rounded,
        size: 22,
        color: onSurface.withValues(alpha: _dropdownIconOpacity),
      ),
      listItemDecoration: ListItemDecoration(
        highlightColor: highlight,
        selectedColor: selectedBg,
        splashColor: Colors.transparent,
      ),
    );
  }

  static CustomDropdownDecoration sidebarTeam(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final selectedBg = isDark
        ? cs.primary.withValues(alpha: 0.22)
        : cs.primaryContainer;

    return CustomDropdownDecoration(
      closedFillColor: cs.surfaceContainer,
      expandedFillColor: cs.surfaceContainer,
      closedBorder: Border.all(color: cs.outlineVariant),
      closedBorderRadius: BorderRadius.circular(8),
      expandedBorder: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.5),
      ),
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
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final selectedBg = isDark
        ? cs.primary.withValues(alpha: 0.2)
        : cs.primaryContainer;

    return CustomDropdownDecoration(
      closedFillColor: cs.surfaceContainerHigh,
      expandedFillColor: cs.surfaceContainer,
      closedBorder: Border.all(color: cs.outlineVariant),
      closedBorderRadius: BorderRadius.circular(borderRadius),
      expandedBorder: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.5),
      ),
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
