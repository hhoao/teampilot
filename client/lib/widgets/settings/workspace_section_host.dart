import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import 'workspace_hub_shell.dart';
import 'workspace_pane_header.dart';
import 'workspace_pane_insets.dart';
import 'workspace_section_compact_shell.dart';
import 'workspace_section_nav_item.dart';
import 'workspace_section_navigation.dart';

class WorkspaceHubDesktopShell extends StatelessWidget {
  const WorkspaceHubDesktopShell({
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    required this.nav,
    required this.body,
    this.pageKey,
    this.onBack,
    this.embedded = false,
    super.key,
  });

  final Key? pageKey;
  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final Widget nav;
  final Widget body;
  final VoidCallback? onBack;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspacePaneHeader(
          title: title,
          subtitle: subtitle,
          showSubtitle: showSubtitle,
          onBack: onBack,
        ),
        Expanded(
          child: BlocBuilder<LayoutCubit, LayoutState>(
            builder: (context, layoutState) {
              return WorkspaceSplitShell(
                navWidth: layoutState.preferences.workspaceNavWidth,
                onNavWidthChanged: (width) {
                  context.read<LayoutCubit>().setWorkspaceNavWidth(width);
                },
                nav: nav,
                body: body,
              );
            },
          ),
        ),
      ],
    );

    if (!embedded) {
      column = Padding(padding: WorkspacePaneInsets.page, child: column);
    }

    return Container(key: pageKey, child: column);
  }
}

enum WorkspaceAdaptiveSectionLayout {
  androidBodyOnly,
  compactTabs,
  desktopSplit,
}

WorkspaceAdaptiveSectionLayout workspaceAdaptiveSectionLayout({
  required bool compactSectionTabs,
  required bool androidHubNavigation,
  required double viewportWidth,
}) {
  if (!compactSectionTabs && androidHubNavigation) {
    return WorkspaceAdaptiveSectionLayout.androidBodyOnly;
  }
  if (compactSectionTabs &&
      viewportWidth < WorkspacePanePolicy.narrowBreakpointWidth) {
    return WorkspaceAdaptiveSectionLayout.compactTabs;
  }
  return WorkspaceAdaptiveSectionLayout.desktopSplit;
}

class WorkspaceAdaptiveSectionPage extends StatelessWidget {
  WorkspaceAdaptiveSectionPage({
    required this.pageKey,
    required this.title,
    required this.body,
    this.nav,
    this.items,
    this.compactSectionTabs = false,
    this.subtitle,
    this.showSubtitle = false,
    this.onBack,
    this.embedded = false,
    super.key,
  }) : assert(
         !compactSectionTabs || (items != null && items.isNotEmpty),
         'compactSectionTabs requires non-empty items',
       ),
       assert(
         compactSectionTabs || nav != null,
         'legacy mode requires nav',
       );

  final Key pageKey;
  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final Widget? nav;
  final List<WorkspaceSectionNavItem>? items;
  final bool compactSectionTabs;
  final Widget body;
  final VoidCallback? onBack;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final layout = workspaceAdaptiveSectionLayout(
      compactSectionTabs: compactSectionTabs,
      androidHubNavigation: useAndroidHubNavigation(context),
      viewportWidth: MediaQuery.sizeOf(context).width,
    );

    switch (layout) {
      case WorkspaceAdaptiveSectionLayout.androidBodyOnly:
        return WorkspaceSectionPage(
          pageKey: pageKey,
          embedded: embedded,
          child: body,
        );
      case WorkspaceAdaptiveSectionLayout.compactTabs:
        return WorkspaceSectionCompactShell(
          pageKey: pageKey,
          title: title,
          subtitle: subtitle,
          showSubtitle: showSubtitle,
          items: items!,
          body: body,
          onBack: onBack,
          embedded: embedded,
        );
      case WorkspaceAdaptiveSectionLayout.desktopSplit:
        return WorkspaceHubDesktopShell(
          pageKey: pageKey,
          title: title,
          subtitle: subtitle,
          showSubtitle: showSubtitle,
          nav: nav ?? _navFromItems(items!),
          body: body,
          onBack: onBack,
          embedded: embedded,
        );
    }
  }
}

Widget _navFromItems(List<WorkspaceSectionNavItem> items) {
  return WorkspaceHubNavList(
    sidebarStyle: true,
    entries: [
      for (final item in items)
        WorkspaceHubEntry(
          title: item.label,
          icon: item.icon ?? Icons.circle_outlined,
          selected: item.selected,
          onTap: item.onSelect,
        ),
    ],
  );
}

class WorkspaceEnumNavPanel<S extends Enum> extends StatelessWidget {
  const WorkspaceEnumNavPanel({
    required this.sections,
    required this.current,
    required this.basePath,
    required this.onSelect,
    required this.descriptor,
    super.key,
  });

  final List<S> sections;
  final S current;
  final String basePath;
  final ValueChanged<S> onSelect;
  final WorkspaceSectionDescriptor Function(S section) descriptor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubNavList(
      sidebarStyle: true,
      entries: [
        for (final section in sections)
          WorkspaceHubEntry(
            title: descriptor(section).title(l10n),
            icon: descriptor(section).icon,
            selected: section == current,
            onTap: () => onSelect(section),
          ),
      ],
    );
  }
}

class WorkspaceCompositeNavPanel extends StatelessWidget {
  const WorkspaceCompositeNavPanel({
    required this.primaryEntries,
    this.trailingChildren = const [],
    super.key,
  });

  final List<WorkspaceHubEntry> primaryEntries;

  /// Sub-menu rows after [primaryEntries] (e.g. members under the Members section).
  final List<Widget> trailingChildren;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: WorkspaceHubNavList(
        entries: primaryEntries,
        trailingChildren: [
          for (final child in trailingChildren)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 2),
              child: child,
            ),
        ],
      ),
    );
  }
}
