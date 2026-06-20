import 'package:flutter/material.dart';

import '../../../models/workspace.dart';
import '../../../models/layout_preferences.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
import 'workspace_sidebar.dart';

class WorkspaceSplitPane extends StatefulWidget {
  const WorkspaceSplitPane({
    required this.workspace,
    required this.isPersonalWorkspace,
    required this.profileId,
    required this.sessionTeamFilter,
    super.key,
  });

  final Workspace workspace;
  final bool isPersonalWorkspace;

  /// The launch identity the workspace was opened against ([LaunchProfile.id]).
  final String profileId;

  /// Empty for personal mode; team id when opened as a team.
  final String sessionTeamFilter;

  @override
  State<WorkspaceSplitPane> createState() => _WorkspaceSplitPaneState();
}

class _WorkspaceSplitPaneState extends State<WorkspaceSplitPane> {
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
            (_sidebarWidth ?? WorkspaceSidebarLayout.defaultWidth).clamp(
              minSidebar,
              maxSidebar,
            );
        return ResizableSplitView(
          first: WorkspaceSidebar(
            workspace: widget.workspace,
            isPersonalWorkspace: widget.isPersonalWorkspace,
            profileId: widget.profileId,
            sessionTeamFilter: widget.sessionTeamFilter,
          ),
          second: ChatPage(
            cwd: widget.workspace.primaryPath,
            additionalPaths: widget.workspace.additionalPaths,
            workspaceId: widget.workspace.workspaceId,
            isPersonalWorkspace: widget.isPersonalWorkspace,
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
