import 'package:flutter/widgets.dart';

import '../../../models/workspace.dart';
import 'workspace_compose_landing_pane.dart';

/// Center pane for the workspace IDE shell.
///
/// When [composeLanding] is true, builds [WorkspaceComposeLandingPane] directly
/// so open does not pay [ChatPage] / ChatPageShell workbench projection cost.
Widget buildWorkspaceIdeCenter({
  required bool composeLanding,
  required Workspace workspace,
  required Widget chatPage,
}) {
  if (composeLanding) {
    return WorkspaceComposeLandingPane(workspace: workspace);
  }
  return chatPage;
}
