import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'custom_dropdown.dart';

const _dropdownBorderRadius = 10.0;
const _dropdownIconOpacity = 0.55;

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
      closedFillColor: cs.workspaceInset,
      expandedFillColor: cs.workspaceCard,
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
      headerStyle: dropdownFieldTextStyle(
        context,
        color: onSurface,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: dropdownHintTextStyle(context),
      listItemStyle: dropdownFieldTextStyle(
        context,
        color: onSurface,
        fontWeight: FontWeight.w500,
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
      closedFillColor: cs.workspaceCard,
      expandedFillColor: cs.workspaceCard,
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
      headerStyle: dropdownFieldTextStyle(
        context,
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: dropdownHintTextStyle(context),
      listItemStyle: dropdownFieldTextStyle(
        context,
        color: onSurface,
        fontWeight: FontWeight.w600,
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
      closedFillColor: cs.workspaceInset,
      expandedFillColor: cs.workspaceCard,
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
      headerStyle: dropdownFieldTextStyle(
        context,
        color: onSurface,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: dropdownHintTextStyle(context),
      listItemStyle: dropdownFieldTextStyle(context, color: onSurface),
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
