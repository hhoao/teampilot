import 'package:flutter/material.dart';

import '../dropdown/custom_dropdown.dart';
import '../dropdown/flashskyai_dropdown_decoration.dart';

const _settingCardBorderRadius = 14.0;
const _settingRowPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);
const _settingGroupHeaderPadding = EdgeInsets.fromLTRB(20, 20, 20, 8);
const _titleSubtitleGap = 4.0;
const _labelTrailingGap = 24.0;

const _dropdownMinWidth = 140.0;

/// Rounded settings panel (card) using global colors and spacing tokens.
class SettingsSurfaceCard extends StatelessWidget {
  const SettingsSurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_settingCardBorderRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: _settingGroupHeaderPadding,
      child: Text(
        title,
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final onSurface = cs.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _settingRowPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: onSurface,
                      ),
                    ),
                    SizedBox(height: _titleSubtitleGap),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: _labelTrailingGap),
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
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
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
    final decoration = FlashskyDropdownDecorations.settingsCompact(context);
    final values = entries.map((e) => e.$1).toList();
    final headerStyle = decoration.headerStyle!;
    final listStyle = decoration.listItemStyle!;

    String labelOf(T item) =>
        entries.firstWhere((e) => e.$1 == item, orElse: () => (item, '$item')).$2;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _dropdownMinWidth),
      child: DropdownFlutter<T>(
        items: values,
        initialItem: value,
        excludeSelected: false,
        onChanged: onChanged,
        decoration: decoration,
        closedHeaderPadding: const EdgeInsets.symmetric(
          horizontal: 8 + 4,
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
