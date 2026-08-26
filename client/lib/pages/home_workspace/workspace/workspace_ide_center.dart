import 'package:flutter/widgets.dart';

import '../../../models/workspace.dart';
import 'workspace_chat_pane.dart';

/// Center pane for the workspace IDE shell.
///
/// When [newChat] is true, builds [WorkspaceChatPane] directly so open does
/// not pay [ChatPage] / ChatPageShell workbench projection cost.
Widget buildWorkspaceIdeCenter({
  required bool newChat,
  required Workspace workspace,
  required Widget chatPage,
  String? initialText,
}) {
  if (newChat) {
    return WorkspaceChatPane(workspace: workspace, initialText: initialText);
  }
  return chatPage;
}
