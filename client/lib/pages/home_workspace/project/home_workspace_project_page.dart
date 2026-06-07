import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/project_profile_cubit.dart';
import '../../../cubits/team_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/layout_preferences.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
import 'home_workspace_conversation_panel.dart';
import 'home_workspace_project_config_workspace.dart';
import 'home_workspace_project_rail.dart';
import 'home_workspace_project_section.dart';
import 'home_workspace_project_settings_view.dart';
import 'home_workspace_project_sidebar.dart';
import 'project_config_section.dart';

/// Project work page.
///
/// Personal projects ([AppProject.teamId] empty): project sidebar + chat or
/// project config (`?view=manage`).
///
/// Team projects: icon rail + conversation tree + chat workbench, or project
/// settings — unchanged from the pre–personal-workspace layout.
class HomeWorkspaceProjectPage extends StatefulWidget {
  const HomeWorkspaceProjectPage({
    required this.projectId,
    this.view,
    this.configSection,
    super.key,
  });

  final String projectId;

  /// `manage` shows project configuration instead of the chat workbench.
  final String? view;

  final ProjectConfigSection? configSection;

  @override
  State<HomeWorkspaceProjectPage> createState() => _HomeWorkspaceProjectPageState();
}

class _HomeWorkspaceProjectPageState extends State<HomeWorkspaceProjectPage> {
  double _sidebarWidth = HomeWorkspaceProjectSidebar.defaultWidth;
  double _conversationPanelWidth = HomeWorkspaceConversationPanel.defaultWidth;
  HomeWorkspaceProjectSection _teamSection =
      HomeWorkspaceProjectSection.conversations;

  bool get _showManage => widget.view == 'manage';

  ProjectConfigSection get _configSection =>
      widget.configSection ?? ProjectConfigSection.settings;

  @override
  void initState() {
    super.initState();
    // Switch the active project bucket synchronously so the very first build of
    // this page publishes THIS project's tabs (no one-frame stale-tab flash).
    // Only `tabs`/`activeTabIndex` change here — no ancestor BlocBuilder selects
    // on those, so this emit does not mark an already-built widget dirty.
    context.read<ChatCubit>().setActiveProject(widget.projectId);
    // Team/profile sync emits on TeamCubit/ProjectProfileCubit (which ancestors
    // listen to); defer it past the current frame to stay build-safe.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProjectContext());
  }

  @override
  void didUpdateWidget(covariant HomeWorkspaceProjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      context.read<ChatCubit>().setActiveProject(widget.projectId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncProjectContext());
    }
  }

  void _syncProjectContext() {
    if (!mounted) return;
    final project = _findProject(
      context.read<ChatCubit>().state.projects,
      widget.projectId,
    );
    if (project == null) return;
    if (project.teamId.isEmpty) {
      _loadPersonalProfile(project.projectId);
      return;
    }
    _syncSelectedTeam(project.teamId);
  }

  void _loadPersonalProfile(String projectId) {
    final cubit = context.read<ProjectProfileCubit>();
    if (cubit.state.projectId == projectId &&
        cubit.state.status == ProjectProfileLoadStatus.ready) {
      return;
    }
    unawaited(cubit.load(projectId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final project = context.select<ChatCubit, AppProject?>(
      (c) => _findProject(c.state.projects, widget.projectId),
    );

    if (project == null) {
      return _MissingProject(label: l10n.homeWorkspaceEmptyProjects);
    }

    if (project.teamId.isEmpty) {
      return _buildPersonalProjectPage(context, project);
    }

    return _buildTeamProjectPage(context, project);
  }

  Widget _buildPersonalProjectPage(BuildContext context, AppProject project) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minSidebar = HomeWorkspaceProjectSidebar.minWidth;
        const minMain = LayoutPreferences.minWorkbenchMainWidth;
        final maxSidebar = (maxW - minMain).clamp(
          minSidebar,
          HomeWorkspaceProjectSidebar.maxWidth,
        );
        final initialSidebar = _sidebarWidth.clamp(minSidebar, maxSidebar);
        return ResizableSplitView(
          first: HomeWorkspaceProjectSidebar(
            project: project,
            manageActive: _showManage,
          ),
          second: _showManage
              ? HomeWorkspaceProjectConfigWorkspace(
                  project: project,
                  section: _configSection,
                )
              : ChatPage(
                  cwd: project.primaryPath,
                  projectId: project.projectId,
                  isPersonalProject: true,
                ),
          initialPrimarySize: initialSidebar,
          minPrimarySize: minSidebar,
          minSecondarySize: minMain,
          maxPrimarySize: maxSidebar,
          onPrimarySizeChanged: (width) {
            setState(() => _sidebarWidth = width);
          },
        );
      },
    );
  }

  Widget _buildTeamProjectPage(BuildContext context, AppProject project) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceProjectRail(
          section: _teamSection,
          isPersonalProject: false,
          onSectionChanged: (section) => setState(() => _teamSection = section),
          onLogoTap: () => context.go('/home-v2'),
        ),
        if (_teamSection == HomeWorkspaceProjectSection.conversations)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                const minPanel = HomeWorkspaceConversationPanel.minWidth;
                const minChat = LayoutPreferences.minWorkbenchMainWidth;
                final maxPanel = (maxW - minChat).clamp(
                  minPanel,
                  HomeWorkspaceConversationPanel.maxWidth,
                );
                final initialPanel = _conversationPanelWidth.clamp(
                  minPanel,
                  maxPanel,
                );
                return ResizableSplitView(
                  first: HomeWorkspaceConversationPanel(project: project),
                  second: ChatPage(
                    cwd: project.primaryPath,
                    projectId: project.projectId,
                  ),
                  initialPrimarySize: initialPanel,
                  minPrimarySize: minPanel,
                  minSecondarySize: minChat,
                  maxPrimarySize: maxPanel,
                  onPrimarySizeChanged: (width) {
                    setState(() => _conversationPanelWidth = width);
                  },
                );
              },
            ),
          )
        else
          HomeWorkspaceProjectSettingsView(project: project),
      ],
    );
  }

  void _syncSelectedTeam(String teamId) {
    if (teamId.isEmpty) return;
    final teamCubit = context.read<TeamCubit>();
    if (teamCubit.state.selectedTeam?.id == teamId) return;
    if (teamCubit.state.selectedTeam?.id != teamId) {
      teamCubit.selectTeam(teamId);
    }
  }

  static AppProject? _findProject(List<AppProject> projects, String id) {
    for (final p in projects) {
      if (p.projectId == id) return p;
    }
    return null;
  }
}

class _MissingProject extends StatelessWidget {
  const _MissingProject({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
}
