import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_workspace_settings_theme.dart';

/// Segmented controls in settings use accent fill when selected (differs from
/// app-wide [SegmentedButtonThemeData], which stays neutral).
ButtonStyle workspaceSettingsEmphasizedSegmentButtonStyle(BuildContext context) {
  final tokens = AppWorkspaceSettingsTokens.of(context);
  final colors = AppColors.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textBase = isDark ? Colors.white : const Color(0xFF111827);
  return ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: WidgetStateProperty.all(
      EdgeInsets.symmetric(
        horizontal: tokens.segmentHorizontalPadding,
        vertical: tokens.segmentVerticalPadding,
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return Colors.white;
      return textBase.withValues(alpha: 0.72);
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return Colors.white;
      return textBase.withValues(alpha: 0.72);
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return colors.accentBlue;
      return colors.inputFill;
    }),
    side: WidgetStateProperty.all(BorderSide(color: colors.border)),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.segmentCornerRadius),
      ),
    ),
  );
}

/// Rounded settings panel (card) using global colors and spacing tokens.
class SettingsSurfaceCard extends StatelessWidget {
  const SettingsSurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tokens = AppWorkspaceSettingsTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.rightPanelBackground,
        borderRadius: BorderRadius.circular(tokens.settingCardBorderRadius),
        border: Border.all(color: colors.subtleBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Section label inside a settings card (e.g. "区域可见性").
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: tokens.settingGroupHeaderPadding,
      child: Text(title, style: tokens.groupHeaderStyle(onSurface)),
    );
  }
}

/// One settings row: title + subtitle on the left, [trailing] on the right.
class SettingsLabeledRow extends StatelessWidget {
  const SettingsLabeledRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.showDividerBelow = true,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: tokens.settingRowPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tokens.rowTitleStyle(onSurface)),
                    SizedBox(height: tokens.titleSubtitleGap),
                    Text(subtitle, style: tokens.rowSubtitleStyle(onSurface)),
                  ],
                ),
              ),
              SizedBox(width: tokens.labelTrailingGap),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(height: 1, thickness: 1, color: colors.subtleBorder),
      ],
    );
  }
}

/// Compact bordered dropdown for settings rows (matches global input colors).
class SettingsCompactDropdown<T> extends StatelessWidget {
  const SettingsCompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: tokens.dropdownMinWidth),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: tokens.dropdownHorizontalPadding),
        decoration: BoxDecoration(
          color: colors.inputFill,
          borderRadius: BorderRadius.circular(tokens.dropdownBorderRadius),
          border: Border.all(color: colors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            borderRadius: BorderRadius.circular(tokens.dropdownBorderRadius),
            icon: Icon(
              Icons.expand_more_rounded,
              color: onSurface.withValues(alpha: tokens.dropdownIconOpacity),
              size: 22,
            ),
            style: TextStyle(
              fontSize: tokens.dropdownLabelFontSize,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
            dropdownColor: colors.rightPanelBackground,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
