import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../dropdown/app_dropdown_field.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../../theme/app_text_styles.dart';
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
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: _settingGroupHeaderPadding,
      child: Text(
        title,
        style: styles.settingsGroupHeaderColored(cs.onSurfaceVariant),
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
    this.titleLeading,
    this.titleTrailing,
    required this.body,
    this.helper,
    this.showDividerBelow = true,
    this.afterTitleBodyGap = 12.0,
  });

  final String title;
  final String? subtitle;

  /// Shown before [title] on the same row.
  final Widget? titleLeading;

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
              if (titleLeading != null || titleTrailing != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (titleLeading != null) ...[
                      titleLeading!,
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: Text(title)),
                    if (titleTrailing != null) titleTrailing!,
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
    this.titleLeading,
    required this.trailing,
    this.showDividerBelow = true,
  });

  final String title;
  final String? subtitle;
  final Widget? titleLeading;
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
              if (titleLeading != null) ...[
                titleLeading!,
                const SizedBox(width: 12),
              ],
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

/// Single-line action buttons for management card headers.
class CardHeaderActionRow extends StatelessWidget {
  const CardHeaderActionRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ],
    );
  }
}

/// Title + optional trailing actions for skills/plugins/MCP cards.
class ManagementCardHeader extends StatelessWidget {
  const ManagementCardHeader({
    required this.title,
    this.trailing,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final titleText = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.of(
        context,
      ).sectionTitle.copyWith(fontWeight: FontWeight.w800, color: textBase),
    );

    if (trailing == null) {
      return titleText;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: titleText,
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: trailing!,
          ),
        ),
      ],
    );
  }
}

/// Small pill showing configured / not configured (workspace CLI, AI features, …).
class SettingsConfiguredBadge extends StatelessWidget {
  const SettingsConfiguredBadge({required this.configured, super.key});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final color = configured ? cs.tertiary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            configured
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            configured
                ? l10n.workspaceCliConfigured
                : l10n.workspaceCliNotConfigured,
            style: styles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
    this.itemBuilder,
    this.listItemBuilder,
  });

  final T value;
  final List<(T value, String label)> entries;
  final ValueChanged<T?> onChanged;
  final Map<T, Key>? itemKeys;
  final Widget Function(BuildContext context, T item)? itemBuilder;
  final Widget Function(BuildContext context, T item)? listItemBuilder;

  @override
  Widget build(BuildContext context) {
    final decoration = AppDropdownDecorations.themed(context);
    final values = entries.map((e) => e.$1).toList();

    String labelOf(T item) => entries
        .firstWhere((e) => e.$1 == item, orElse: () => (item, '$item'))
        .$2;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _dropdownMinWidth),
      child: AppDropdownField<T>(
        items: values,
        initialItem: value,
        onChanged: onChanged,
        decoration: decoration,
        listItemKey: itemKeys == null ? null : (item) => itemKeys![item],
        itemLabel: itemBuilder == null && listItemBuilder == null
            ? labelOf
            : null,
        itemBuilder: itemBuilder,
        listItemBuilder: listItemBuilder,
      ),
    );
  }
}

/// Collapsed-by-default panel for infrequently edited member/workspace options.
class SettingsAdvancedExpansion extends StatelessWidget {
  const SettingsAdvancedExpansion({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: _settingRowPadding,
        expandedAlignment: Alignment.centerLeft,
        childrenPadding: EdgeInsets.zero,
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: _hasSettingsSubtitle(subtitle)
            ? Padding(
                padding: const EdgeInsets.only(top: _titleSubtitleGap),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            : null,
        children: children,
      ),
    );
  }
}
