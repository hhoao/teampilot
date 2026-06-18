import 'package:flutter/material.dart';

import '../../../models/app_project.dart';
import '../../../models/layout_preferences.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
import 'home_workspace_project_sidebar.dart';

class HomeWorkspaceProjectSplitPane extends StatefulWidget {
  const HomeWorkspaceProjectSplitPane({
    required this.project,
    required this.isPersonalProject,
    required this.sessionTeamFilter,
    super.key,
  });

  final AppProject project;
  final bool isPersonalProject;

  /// Empty for personal mode; team id when opened as a team.
  final String sessionTeamFilter;

  @override
  State<HomeWorkspaceProjectSplitPane> createState() =>
      _HomeWorkspaceProjectSplitPaneState();
}

class _HomeWorkspaceProjectSplitPaneState
    extends State<HomeWorkspaceProjectSplitPane> {
  double? _sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minMain = LayoutPreferences.minWorkbenchMainWidth;
        const minSidebar = HomeWorkspaceProjectSidebarLayout.minWidth;
        const maxSidebarCap = HomeWorkspaceProjectSidebarLayout.maxWidth;
        final maxSidebar = (maxW - minMain).clamp(minSidebar, maxSidebarCap);
        final initialSidebar =
            (_sidebarWidth ?? HomeWorkspaceProjectSidebarLayout.defaultWidth)
                .clamp(minSidebar, maxSidebar);
        return ResizableSplitView(
          first: HomeWorkspaceProjectSidebar(
            project: widget.project,
            isPersonalProject: widget.isPersonalProject,
            sessionTeamFilter: widget.sessionTeamFilter,
          ),
          second: ChatPage(
            cwd: widget.project.primaryPath,
            projectId: widget.project.projectId,
            isPersonalProject: widget.isPersonalProject,
          ),
          initialPrimarySize: initialSidebar,
          minPrimarySize: minSidebar,
          minSecondarySize: minMain,
          maxPrimarySize: maxSidebar,
          onPrimarySizeChanged: (width) => _sidebarWidth = width,
        );
      },
    );
  }
}
