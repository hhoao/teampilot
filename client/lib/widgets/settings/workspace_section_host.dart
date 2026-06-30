import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import 'workspace_hub_shell.dart';
import 'workspace_section_navigation.dart';

class WorkspaceHubDesktopShell extends StatelessWidget {
  const WorkspaceHubDesktopShell({
    required this.title,
    required this.subtitle,
    required this.nav,
    required this.body,
    this.pageKey,
    super.key,
  });

  final Key? pageKey;
  final String title;
  final String subtitle;
  final Widget nav;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: pageKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(title: title, subtitle: subtitle),
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
      ),
    );
  }
}

class WorkspaceAdaptiveSectionPage extends StatelessWidget {
  const WorkspaceAdaptiveSectionPage({
    required this.pageKey,
    required this.title,
    required this.subtitle,
    required this.nav,
    required this.body,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String subtitle;
  final Widget nav;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (useAndroidHubNavigation(context)) {
      return WorkspaceSectionPage(pageKey: pageKey, child: body);
    }
    return WorkspaceHubDesktopShell(
      pageKey: pageKey,
      title: title,
      subtitle: subtitle,
      nav: nav,
      body: body,
    );
  }
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
