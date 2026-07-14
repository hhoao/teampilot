import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../pane_entry_animation.dart';
import '../split_layout.dart';

enum WorkspaceHubNavDensity { standard, relaxed, subItem }

/// One row in a hub list or desktop side nav.
class WorkspaceHubEntry {
  const WorkspaceHubEntry({
    required this.title,
    required this.icon,
    required this.onTap,
    this.key,
    this.selected = false,
    this.trailingIcon,
    this.showLeaderBadge = false,
    this.density = WorkspaceHubNavDensity.standard,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Key? key;
  final bool selected;
  final IconData? trailingIcon;
  final bool showLeaderBadge;
  final WorkspaceHubNavDensity density;
}

/// Page header used on hub and desktop workspace shells.
class WorkspaceHubTitleBar extends StatelessWidget {
  const WorkspaceHubTitleBar({
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.onBack,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final back = onBack;
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(20, 20, 20, 16)
          : const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (back != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: context.l10n.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: back,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _titleBlock(context, textBase)),
              ],
            )
          else
            _titleBlock(context, textBase),
        ],
      ),
    );
  }

  Widget _titleBlock(BuildContext context, Color textBase) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.of(context).lgSemiboldSnugColored(textBase),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.of(context).mdColored(
            textBase.withValues(alpha: 0.66),
          ),
        ),
      ],
    );
  }
}

class WorkspaceHubNavItem extends StatelessWidget {
  const WorkspaceHubNavItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.hubStyle = false,
    this.trailingIcon,
    this.showLeaderBadge = false,
    this.density = WorkspaceHubNavDensity.standard,
    super.key,
  });

  /// Leading icon for team-lead rows (others use [Icons.person_outline]).
  static const teamLeadNavIcon = Icons.workspace_premium_outlined;

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool hubStyle;
  final IconData? trailingIcon;
  final bool showLeaderBadge;
  final WorkspaceHubNavDensity density;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedFg = cs.onPrimaryContainer;
    final normalFg = cs.onSurface.withValues(alpha: hubStyle ? 0.92 : 0.88);
    final muted = cs.onSurfaceVariant;
    final selectedColor = cs.primaryContainer;
    final trailing = trailingIcon ?? (hubStyle ? Icons.chevron_right : null);

    final (height, iconSize, horizontalPadding, leftIndent) = switch (density) {
      WorkspaceHubNavDensity.standard => (
        hubStyle ? 56.0 : 48.0,
        context.appIconSizes.md,
        hubStyle ? 16.0 : 18.0,
        0.0,
      ),
      WorkspaceHubNavDensity.relaxed => (
        54.0,
        context.appIconSizes.md,
        18.0,
        0.0,
      ),
      WorkspaceHubNavDensity.subItem => (
        44.0,
        context.appIconSizes.md,
        14.0,
        14.0,
      ),
    };

    final borderRadius = density == WorkspaceHubNavDensity.subItem
        ? BorderRadius.circular(10)
        : BorderRadius.circular(12);
    final leadingIcon = showLeaderBadge ? teamLeadNavIcon : icon;

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(left: leftIndent, bottom: 8),
        child: Material(
          color: selected
              ? selectedColor
              : hubStyle
              ? cs.workspaceSubtleSurface
              : Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  children: [
                    Icon(
                      leadingIcon,
                      color: selected ? selectedFg : muted,
                      size: iconSize,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (hubStyle
                                          ? AppTextStyles.of(
                                              context,
                                            ).mdSemiboldTightSnug
                                          : AppTextStyles.of(context).md)
                                      .copyWith(
                                        color: selected ? selectedFg : normalFg,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null)
                      Icon(
                        trailing,
                        size: hubStyle ? 22 : 18,
                        color: selected ? selectedFg : muted,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceHubNavList extends StatelessWidget {
  const WorkspaceHubNavList({
    required this.entries,
    this.hubStyle = false,
    this.sidebarStyle = false,
    this.shrinkWrap = false,
    this.trailingChildren = const [],
    super.key,
  });

  final List<WorkspaceHubEntry> entries;
  final bool hubStyle;
  final bool sidebarStyle;

  /// When true, sizes to [entries] height. Use inside a [Column] with a
  /// scrollable sibling (e.g. member list footer), not inside another scroll view.
  final bool shrinkWrap;

  /// Extra rows after [entries] in the same scroll view (e.g. member sub-items).
  final List<Widget> trailingChildren;

  @override
  Widget build(BuildContext context) {
    final items = entries.map((entry) {
      return WorkspaceHubNavItem(
        key: entry.key,
        title: entry.title,
        icon: entry.icon,
        selected: entry.selected,
        hubStyle: hubStyle,
        trailingIcon: entry.trailingIcon,
        showLeaderBadge: entry.showLeaderBadge,
        density: entry.density,
        onTap: entry.onTap,
      );
    }).toList();

    final scrollPhysics = shrinkWrap
        ? const NeverScrollableScrollPhysics()
        : null;

    final children = [...items, ...trailingChildren];

    if (hubStyle) {
      return ListView(
        shrinkWrap: shrinkWrap,
        physics: scrollPhysics,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: children,
      );
    }

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: scrollPhysics,
      padding: sidebarStyle
          ? const EdgeInsets.fromLTRB(24, 28, 18, 24)
          : EdgeInsets.zero,
      children: children,
    );
  }
}

/// Android hub landing: title + tappable section list.
class WorkspaceHubPage extends StatelessWidget {
  const WorkspaceHubPage({
    required this.pageKey,
    required this.title,
    required this.subtitle,
    required this.entries,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String subtitle;
  final List<WorkspaceHubEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: pageKey,
      color: cs.workspacePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(title: title, subtitle: subtitle, compact: true),
          Expanded(
            child: WorkspaceHubNavList(entries: entries, hubStyle: true),
          ),
        ],
      ),
    );
  }
}

/// Desktop split: resizable nav column + scrollable body.
class WorkspaceSplitShell extends StatelessWidget {
  const WorkspaceSplitShell({
    required this.nav,
    required this.body,
    this.navWidth = LayoutPreferences.defaultWorkspaceNavWidth,
    this.onNavWidthChanged,
    super.key,
  });

  final Widget nav;
  final Widget body;
  final double navWidth;
  final ValueChanged<double>? onNavWidthChanged;

  static const compactBreakpoint = 820.0;
  static const _bodySwitchDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBreakpoint;
        final contentPadding = compact
            ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
            : const EdgeInsets.fromLTRB(24, 28, 28, 24);

        return TwoPaneSplitView(
          axis: Axis.horizontal,
          first: nav,
          second: Padding(
            padding: contentPadding,
            child: LayoutBuilder(
              builder: (context, inner) {
                final w = inner.maxWidth;
                final bodyMaxWidth = w.isFinite
                    ? w.clamp(480.0, 3200.0)
                    : 3200.0;
                final contentWidth = w.isFinite && w < bodyMaxWidth
                    ? w
                    : bodyMaxWidth;
                return SizedBox(
                  width: contentWidth,
                  height: inner.maxHeight,
                  child: _HubBodySwitcher(body: body),
                );
              },
            ),
          ),
          initialSize: navWidth,
          minSize: LayoutPreferences.minWorkspaceNavWidth,
          minSecondarySize: LayoutPreferences.minWorkspaceHubContentWidth,
          maxSize: LayoutPreferences.maxWorkspaceNavWidth,
          onSizeChanged: onNavWidthChanged,
        );
      },
    );
  }
}

/// Fade + slide when hub section body identity changes.
class _HubBodySwitcher extends StatelessWidget {
  const _HubBodySwitcher({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.disableAnimationsOf(context);
    final duration = disabled ? Duration.zero : WorkspaceSplitShell._bodySwitchDuration;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Keep only the incoming child so outgoing/incoming never stack.
      layoutBuilder: (current, _) => current ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) =>
          paneSwitcherStructuralTransition(child, animation, context),
      child: KeyedSubtree(
        key: body.key ?? ValueKey<Type>(body.runtimeType),
        child: body,
      ),
    );
  }
}

/// Android detail page chrome: full-width body with standard inset.
class WorkspaceSectionPage extends StatelessWidget {
  const WorkspaceSectionPage({
    required this.pageKey,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    super.key,
  });

  final Key pageKey;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: pageKey,
      color: cs.workspacePage,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: child)],
        ),
      ),
    );
  }
}

/// Section title inside a detail pane (desktop; hidden on Android when AppBar shows title).
class WorkspaceSectionHeading extends StatelessWidget {
  const WorkspaceSectionHeading({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: styles.lgSemiboldSnugColored(cs.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: styles.mutedMd,
        ),
      ],
    );
  }
}
