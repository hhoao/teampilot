import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_workspace_settings_theme.dart';
import '../dropdown/custom_dropdown.dart';
import '../dropdown/flashskyai_dropdown_decoration.dart';

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
class SettingsCompactDropdown<T extends Object> extends StatelessWidget {
  const SettingsCompactDropdown({
    super.key,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.itemKeys,
  });

  final T value;
  final List<(T value, String label)> entries;
  final ValueChanged<T?> onChanged;
  final Map<T, Key>? itemKeys;

  @override
  Widget build(BuildContext context) {
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final decoration = FlashskyDropdownDecorations.settingsCompact(context);
    final values = entries.map((e) => e.$1).toList();
    final headerStyle = decoration.headerStyle!;
    final listStyle = decoration.listItemStyle!;

    String labelOf(T item) =>
        entries.firstWhere((e) => e.$1 == item, orElse: () => (item, '$item')).$2;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: tokens.dropdownMinWidth),
      child: DropdownFlutter<T>(
        items: values,
        initialItem: value,
        excludeSelected: false,
        onChanged: onChanged,
        decoration: decoration,
        closedHeaderPadding: EdgeInsets.symmetric(
          horizontal: 8 + tokens.dropdownHorizontalPadding,
          vertical: 8,
        ),
        expandedHeaderPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        listItemPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        overlayHeight: 220,
        headerBuilder: (context, item, _) => Text(
          labelOf(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: headerStyle,
        ),
        listItemBuilder: (context, item, isSelected, _) {
          final key = itemKeys?[item];
          return Row(
            children: [
              Expanded(
                child: Text(
                  labelOf(item),
                  key: key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: listStyle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
