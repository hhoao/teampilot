import 'package:flutter/material.dart';

import '../../../models/app_project.dart';
import '../../../models/layout_preferences.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
import 'home_workspace_project_sidebar.dart';

class WorkspaceSplitPane extends StatefulWidget {
  const WorkspaceSplitPane({
    required this.project,
    required this.isPersonalProject,
    required this.identityId,
    required this.sessionTeamFilter,
    super.key,
  });

  final Workspace project;
  final bool isPersonalProject;

  /// The launch identity the project was opened against ([Identity.id]).
  final String identityId;

  /// Empty for personal mode; team id when opened as a team.
  final String sessionTeamFilter;

  @override
  State<WorkspaceSplitPane> createState() =>
      _WorkspaceSplitPaneState();
}

class _WorkspaceSplitPaneState
    extends State<WorkspaceSplitPane> {
  double? _sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minMain = LayoutPreferences.minWorkbenchMainWidth;
        const minSidebar = WorkspaceSidebarLayout.minWidth;
        const maxSidebarCap = WorkspaceSidebarLayout.maxWidth;
        final maxSidebar = (maxW - minMain).clamp(minSidebar, maxSidebarCap);
        final initialSidebar =
            (_sidebarWidth ?? WorkspaceSidebarLayout.defaultWidth)
                .clamp(minSidebar, maxSidebar);
        return ResizableSplitView(
          first: WorkspaceSidebar(
            project: widget.project,
            isPersonalProject: widget.isPersonalProject,
            identityId: widget.identityId,
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
