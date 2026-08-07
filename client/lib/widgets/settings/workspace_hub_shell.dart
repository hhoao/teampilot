import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/layout_preferences.dart';
import '../../theme/workspace_surface_layers.dart';
import '../pane_entry_animation.dart';
import '../split_layout.dart';
import 'workspace_pane_header.dart';
import 'workspace_pane_insets.dart';

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
        context.tpIconSizes.md,
        hubStyle ? 16.0 : 18.0,
        0.0,
      ),
      WorkspaceHubNavDensity.relaxed => (
        54.0,
        context.tpIconSizes.md,
        18.0,
        0.0,
      ),
      WorkspaceHubNavDensity.subItem => (
        44.0,
        context.tpIconSizes.md,
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
        child: TpHover(
          backgroundColor: selected
              ? selectedColor
              : hubStyle
              ? cs.workspaceSubtleSurface
              : Colors.transparent,
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
                                          ? TpTextStyles.of(
                                              context,
                                            ).mdSemiboldTightSnug
                                          : TpTextStyles.of(context).md)
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
    this.subtitle,
    this.showSubtitle = false,
    required this.entries,
    this.embedded = false,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final List<WorkspaceHubEntry> entries;

  /// When true, skip page inset and page fill — parent card chrome already
  /// supplies [ColorScheme.workspaceCard].
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspacePaneHeader(
          title: title,
          subtitle: subtitle,
          showSubtitle: showSubtitle,
        ),
        Expanded(
          child: WorkspaceHubNavList(entries: entries, hubStyle: true),
        ),
      ],
    );

    if (!embedded) {
      column = Padding(padding: WorkspacePaneInsets.page, child: column);
    }

    return Container(
      key: pageKey,
      // Transparent when embedded so home [WorkspacePageCardShell] card fill
      // is not overwritten by [workspacePage].
      color: embedded ? null : cs.workspacePage,
      child: column,
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

/// Fade + slide entry when hub section body identity changes — same motion as
/// home left-nav pane switches ([PaneEntryAnimation] / workspace pane data).
class _HubBodySwitcher extends StatelessWidget {
  const _HubBodySwitcher({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final identity = body.key ?? ValueKey<Type>(body.runtimeType);
    return PaneEntryAnimation(
      key: identity,
      duration: WorkspaceSplitShell._bodySwitchDuration,
      child: body,
    );
  }
}

/// Android detail page chrome: full-width body with standard inset.
class WorkspaceSectionPage extends StatelessWidget {
  const WorkspaceSectionPage({
    required this.pageKey,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.embedded = false,
    super.key,
  });

  final Key pageKey;
  final Widget child;
  final EdgeInsets padding;

  /// When true, skip page fill — parent card chrome already supplies
  /// [ColorScheme.workspaceCard] (e.g. home MCP / plugins / extensions).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: pageKey,
      // Transparent when embedded so home [WorkspacePageCardShell] card fill
      // is not overwritten by [workspacePage].
      color: embedded ? null : cs.workspacePage,
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
