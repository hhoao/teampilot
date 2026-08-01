import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import 'workspace_hub_shell.dart';
import 'workspace_pane_header.dart';
import 'workspace_pane_insets.dart';
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

class WorkspaceAdaptiveSectionPage extends StatelessWidget {
  const WorkspaceAdaptiveSectionPage({
    required this.pageKey,
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    required this.nav,
    required this.body,
    this.onBack,
    this.embedded = false,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final Widget nav;
  final Widget body;
  final VoidCallback? onBack;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (useAndroidHubNavigation(context)) {
      return WorkspaceSectionPage(pageKey: pageKey, child: body);
    }
    return WorkspaceHubDesktopShell(
      pageKey: pageKey,
      title: title,
      subtitle: subtitle,
      showSubtitle: showSubtitle,
      nav: nav,
      body: body,
      onBack: onBack,
      embedded: embedded,
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
