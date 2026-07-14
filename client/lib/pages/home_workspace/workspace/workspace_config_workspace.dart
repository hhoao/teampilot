import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/workspace_project_config_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/workspace_chrome_profile.dart';
import '../../../utils/workspace_display_name.dart';
import '../../../widgets/settings/workspace_section_host.dart';
import 'config/workspace_extensions_section.dart';
import 'config/workspace_mcp_section.dart';
import 'config/workspace_plugins_section.dart';
import 'config/workspace_skills_section.dart';
import 'workspace_config_nav_panel.dart';
import 'workspace_config_section.dart';
import 'workspace_info_section.dart';
import '../home_workspace_route.dart';

/// Project-scoped workspace configuration (settings + resource bindings).
class WorkspaceConfigPanel extends StatefulWidget {
  const WorkspaceConfigPanel({
    required this.workspace,
    required this.section,
    super.key,
  });

  final Workspace workspace;
  final WorkspaceConfigSection section;

  @override
  State<WorkspaceConfigPanel> createState() => _WorkspaceConfigPanelState();
}

class _WorkspaceConfigPanelState extends State<WorkspaceConfigPanel> {
  String _managePath(WorkspaceConfigSection section) {
    return Uri(
      path: '/home-v2/workspace/${widget.workspace.workspaceId}',
      queryParameters: {
        'view': 'manage',
        'section': section.routeSegment,
      },
    ).toString();
  }

  void _leaveManage() {
    final location = GoRouterState.of(context).uri.toString();
    final routeProfile = HomeWorkspaceRoute.profile(location);
    final profileId = workspaceChromeProfileId(
      widget.workspace,
      routeProfileId: routeProfile,
    );
    context.go(
      Uri(
        path: '/home-v2/workspace/${widget.workspace.workspaceId}',
        queryParameters: {'profile': profileId},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = WorkspaceConfigSection.sections;
    final section = sections.contains(widget.section)
        ? widget.section
        : WorkspaceConfigSection.settings;

    return BlocProvider(
      create: (context) => WorkspaceProjectConfigCubit(
        repository: context.read<WorkspaceProjectConfigRepository>(),
        workspaceId: widget.workspace.workspaceId,
      )..load(),
      child: WorkspaceAdaptiveSectionPage(
        pageKey: AppKeys.workspaceConfigWorkspace,
        title: l10n.homeWorkspaceWorkspaceManagement,
        subtitle: widget.workspace.localizedName(l10n),
        onBack: _leaveManage,
        nav: WorkspaceConfigNavPanel(
          sections: sections,
          section: section,
          l10n: l10n,
          onSelect: (s) => context.go(_managePath(s)),
        ),
        body: KeyedSubtree(
          key: ValueKey(section),
          child: _ProjectConfigBody(
            workspace: widget.workspace,
            section: section,
          ),
        ),
      ),
    );
  }
}

class _ProjectConfigBody extends StatelessWidget {
  const _ProjectConfigBody({
    required this.workspace,
    required this.section,
  });

  final Workspace workspace;
  final WorkspaceConfigSection section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      WorkspaceConfigSection.settings => WorkspaceInfoSection(workspace: workspace),
      WorkspaceConfigSection.skills => WorkspaceSkillsSection(
        workspaceId: workspace.workspaceId,
      ),
      WorkspaceConfigSection.plugins => WorkspacePluginsSection(
        workspaceId: workspace.workspaceId,
      ),
      WorkspaceConfigSection.mcp => WorkspaceMcpSection(
        workspaceId: workspace.workspaceId,
      ),
      WorkspaceConfigSection.extensions => WorkspaceExtensionsSection(
        workspaceId: workspace.workspaceId,
      ),
    };
  }
}
