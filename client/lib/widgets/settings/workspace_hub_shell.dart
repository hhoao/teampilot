import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/layout_preferences.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../resizable_split_view.dart';

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
    this.density = WorkspaceHubNavDensity.standard,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Key? key;
  final bool selected;
  final IconData? trailingIcon;
  final WorkspaceHubNavDensity density;
}

/// Page header used on hub and desktop workspace shells.
class WorkspaceHubTitleBar extends StatelessWidget {
  const WorkspaceHubTitleBar({
    required this.title,
    required this.subtitle,
    this.compact = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(20, 20, 20, 16)
          : const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: cs.workspacePage,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.of(context).subtitle.copyWith(
              color: textBase,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: textBase.withValues(alpha: 0.66),
            ),
          ),
        ],
      ),
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
    this.density = WorkspaceHubNavDensity.standard,
    super.key,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool hubStyle;
  final IconData? trailingIcon;
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
        18.0,
        hubStyle ? 16.0 : 18.0,
        0.0,
      ),
      WorkspaceHubNavDensity.relaxed => (54.0, 21.0, 18.0, 0.0),
      WorkspaceHubNavDensity.subItem => (44.0, 19.0, 14.0, 14.0),
    };

    final borderRadius = density == WorkspaceHubNavDensity.subItem
        ? BorderRadius.circular(10)
        : BorderRadius.circular(12);

    return Padding(
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
                    icon,
                    color: selected ? selectedFg : muted,
                    size: iconSize,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (hubStyle
                              ? AppTextStyles.of(context).sectionTitle
                              : AppTextStyles.of(context).body)
                          .copyWith(
                        fontWeight: hubStyle
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? selectedFg : normalFg,
                      ),
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
    this.animateEntries = false,
    super.key,
  });

  final List<WorkspaceHubEntry> entries;
  final bool hubStyle;
  final bool sidebarStyle;
  final bool animateEntries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = entries.indexed.map((indexedEntry) {
      final (index, entry) = indexedEntry;
      final item = WorkspaceHubNavItem(
        key: entry.key,
        title: entry.title,
        icon: entry.icon,
        selected: entry.selected,
        hubStyle: hubStyle,
        trailingIcon: entry.trailingIcon,
        density: entry.density,
        onTap: entry.onTap,
      );

      if (!animateEntries) {
        return item;
      }

      return item
          .animate(delay: (index * 35).ms)
          .fadeIn(duration: 180.ms, curve: Curves.easeOut)
          .slideX(
            begin: -0.06,
            end: 0,
            duration: 220.ms,
            curve: Curves.easeOutCubic,
          );
    }).toList();

    if (hubStyle) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: items,
      );
    }

    return Container(
      color: cs.workspacePage,
      padding: sidebarStyle
          ? const EdgeInsets.fromLTRB(24, 28, 18, 24)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
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
    this.bodyAnimationKey,
    super.key,
  });

  final Widget nav;
  final Widget body;
  final double navWidth;
  final ValueChanged<double>? onNavWidthChanged;
  final Key? bodyAnimationKey;

  static const compactBreakpoint = 820.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBreakpoint;
        final contentPadding = compact
            ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
            : const EdgeInsets.fromLTRB(24, 28, 28, 24);

        final animatedBody = bodyAnimationKey == null
            ? body
            : body
                  .animate(key: bodyAnimationKey)
                  .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                  .slideX(
                    begin: 0.025,
                    end: 0,
                    duration: 220.ms,
                    curve: Curves.easeOutCubic,
                  );

        return ResizableSplitView(
          initialLeftWidth: navWidth,
          minLeftWidth: LayoutPreferences.minWorkspaceNavWidth,
          maxLeftWidth: LayoutPreferences.maxWorkspaceNavWidth,
          onWidthChanged: onNavWidthChanged,
          left: nav,
          right: Padding(
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
                  child: animatedBody,
                );
              },
            ),
          ),
        );
      },
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
