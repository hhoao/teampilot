import 'package:flutter/material.dart';

import '../dropdown/app_dropdown_field.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../../theme/workspace_surface_layers.dart';

export '../../theme/workspace_surface_layers.dart';

const _settingCardBorderRadius = 14.0;
const _settingRowPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);
const _settingGroupHeaderPadding = EdgeInsets.fromLTRB(20, 20, 20, 8);
const _titleSubtitleGap = 4.0;
const _titleOnlyBodyGap = 8.0;
const _labelTrailingGap = 24.0;

bool _hasSettingsSubtitle(String? subtitle) =>
    subtitle != null && subtitle.trim().isNotEmpty;

const _dropdownMinWidth = 140.0;

/// Rounded settings panel (card) using global colors and spacing tokens.
class SettingsSurfaceCard extends StatelessWidget {
  const SettingsSurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: workspaceCardDecoration(
        cs,
        radius: _settingCardBorderRadius,
        borderAlpha: 0.5,
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

/// Title + subtitle on top; [body] stretches full width on the row below.
///
/// Use when controls need more horizontal space than a side-by-side
/// [SettingsLabeledRow] allows.
class SettingsLabeledStackedRow extends StatelessWidget {
  const SettingsLabeledStackedRow({
    super.key,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    required this.body,
    this.helper,
    this.showDividerBelow = true,
    this.afterTitleBodyGap = 12.0,
  });

  final String title;
  final String? subtitle;

  /// Shown on the same row as [title], aligned to the trailing edge.
  final Widget? titleTrailing;
  final Widget body;

  /// Muted caption below [body], inside the same padded block as the labels.
  final Widget? helper;
  final bool showDividerBelow;

  /// Vertical gap between subtitle and [body].
  final double afterTitleBodyGap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasSubtitle = _hasSettingsSubtitle(subtitle);
    final subtitleStyle = tt.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _settingRowPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (titleTrailing != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Text(title)),
                    titleTrailing!,
                  ],
                )
              else
                Text(title),
              if (hasSubtitle) ...[
                SizedBox(height: _titleSubtitleGap),
                Text(subtitle!.trim(), style: subtitleStyle),
              ],
              SizedBox(
                height: hasSubtitle ? afterTitleBodyGap : _titleOnlyBodyGap,
              ),
              body,
              if (helper != null) ...[const SizedBox(height: 10), helper!],
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

/// One settings row: title + subtitle on the left, [trailing] on the right.
class SettingsLabeledRow extends StatelessWidget {
  const SettingsLabeledRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.showDividerBelow = true,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasSubtitle = _hasSettingsSubtitle(subtitle);
    final subtitleStyle = tt.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );
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
                    Text(title),
                    if (hasSubtitle) ...[
                      SizedBox(height: _titleSubtitleGap),
                      Text(subtitle!.trim(), style: subtitleStyle),
                    ],
                  ],
                ),
              ),
              SizedBox(width: _labelTrailingGap),
              Flexible(
                fit: FlexFit.loose,
                child: Align(alignment: Alignment.centerRight, child: trailing),
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
    final decoration = AppDropdownDecorations.themed(context);
    final values = entries.map((e) => e.$1).toList();

    String labelOf(T item) => entries
        .firstWhere((e) => e.$1 == item, orElse: () => (item, '$item'))
        .$2;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _dropdownMinWidth),
      child: FlashskyDropdownField<T>(
        items: values,
        initialItem: value,
        onChanged: onChanged,
        decoration: decoration,
        listItemKey: itemKeys == null ? null : (item) => itemKeys![item],
        itemLabel: labelOf,
      ),
    );
  }
}
