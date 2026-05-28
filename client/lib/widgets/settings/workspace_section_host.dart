import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../theme/workspace_surface_layers.dart';
import 'workspace_hub_shell.dart';
import 'workspace_section_navigation.dart';

class WorkspaceHubDesktopShell extends StatelessWidget {
  const WorkspaceHubDesktopShell({
    required this.title,
    required this.subtitle,
    required this.nav,
    required this.body,
    this.bodyAnimationKey,
    this.pageKey,
    super.key,
  });

  final Key? pageKey;
  final String title;
  final String subtitle;
  final Widget nav;
  final Widget body;
  final Key? bodyAnimationKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: pageKey,
      color: cs.workspacePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(title: title, subtitle: subtitle),
          Expanded(
            child: BlocBuilder<LayoutCubit, LayoutState>(
              builder: (context, layoutState) {
                return WorkspaceSplitShell(
                  bodyAnimationKey: bodyAnimationKey,
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
    this.bodyAnimationKey,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String subtitle;
  final Widget nav;
  final Widget body;
  final Key? bodyAnimationKey;

  @override
  Widget build(BuildContext context) {
    if (useAndroidHubNavigation(context)) {
      return WorkspaceSectionPage(pageKey: pageKey, child: body);
    }
    return WorkspaceHubDesktopShell(
      pageKey: pageKey,
      title: title,
      subtitle: subtitle,
      bodyAnimationKey: bodyAnimationKey,
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
      animateEntries: true,
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
    this.footer,
    super.key,
  });

  final List<WorkspaceHubEntry> primaryEntries;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.workspacePage,
      padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubNavList(entries: primaryEntries, animateEntries: true),
          if (footer != null) ...[
            const SizedBox(height: 4),
            Expanded(child: footer!),
          ],
        ],
      ),
    );
  }
}
