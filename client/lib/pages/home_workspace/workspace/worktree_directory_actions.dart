import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/git/worktree_removal.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session/session_project_grouping.dart';
import '../../../utils/session/session_worktree_grouping.dart';
import '../../../utils/session/workspace_sessions.dart';
import '../../../widgets/app_toast/app_toast.dart';
import '../../../widgets/home_storage_scope.dart';
import 'worktree_delete_dialog.dart';

enum WorktreeDirectoryMenuAction { newConversation, copyPath, remove }

bool worktreeManagementEnabled(RuntimeContext workContext) =>
    workContext.mode == StorageBackendMode.native ||
    workContext.mode == StorageBackendMode.wsl ||
    workContext.mode == StorageBackendMode.ssh;

Future<WorktreeDirectoryMenuAction?> showWorktreeDirectoryContextMenu(
  BuildContext context, {
  required TapDownDetails tapDetails,
  required String? launchPath,
  required bool canRemove,
}) async {
  final l10n = context.l10n;
  final specs = [
    if (launchPath != null) ...[
      TpActionMenuSpec.item(
        value: WorktreeDirectoryMenuAction.newConversation,
        icon: Icons.edit_outlined,
        label: l10n.worktreeNewConversationHere,
      ),
      TpActionMenuSpec.item(
        value: WorktreeDirectoryMenuAction.copyPath,
        icon: Icons.copy_rounded,
        label: l10n.worktreeMenuCopyPath,
      ),
    ],
    if (canRemove)
      TpActionMenuSpec.item(
        value: WorktreeDirectoryMenuAction.remove,
        icon: Icons.delete_outline_rounded,
        label: l10n.worktreeMenuRemove,
        destructive: true,
      ),
  ];
  if (specs.isEmpty) return null;
  final selected =
      await showTpActionMenuFromSpecsAtTap<WorktreeDirectoryMenuAction>(
        context: context,
        tapDetails: tapDetails,
        specs: specs,
      );
  return selected;
}

Future<void> copyWorktreeDirectoryPath(String path) async {
  await Clipboard.setData(ClipboardData(text: path));
}

/// Confirms and removes a non-main worktree together with its optional
/// conversations. Shared by the project-tree and grouped-sidebar views.
Future<void> confirmAndRemoveWorktree({
  required BuildContext context,
  required WorktreeGroup group,
  required Workspace workspace,
  required String branchLabel,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final cubit = context.read<WorktreeCubit>();
  final l10n = context.l10n;
  final worktreesByProject = {
    for (final folder in workspace.folders)
      folder.path: cubit.worktreesForProject(folder.path),
  };
  final sessionsInGroup = unfilteredSessionsForWorktreeGroup(
    group: group,
    folders: workspace.folders,
    worktreesByProjectPath: worktreesByProject,
    sessions: sessionsForWorkspace(workspace, chatCubit.state.sessions),
    usesPosixPaths: homeStorageOf(context).usesPosixPaths,
  );
  final working = chatCubit.state.busySessionIds;
  final hasBusy = sessionsInGroup.any(
    (session) => working.contains(session.sessionId),
  );
  if (hasBusy) {
    AppToast.show(
      context,
      message: l10n.worktreeDeleteBusyWarning,
      variant: TpToastVariant.error,
    );
    return;
  }

  final tools = WorkspaceToolsScope.maybeOf(context)?.tools;
  final service = tools == null
      ? null
      : GitWorktreeService.forContext(tools.context);
  final dirty = service == null
      ? false
      : await service.isDirty(group.worktree!.path);
  if (!context.mounted) return;
  final result = await showWorktreeDeleteDialog(
    context,
    branchLabel: branchLabel,
    sessionCount: sessionsInGroup.length,
    requireForce: dirty,
  );
  if (result == null || service == null) return;

  try {
    final projectPath = group.projectFolderPath?.trim() ?? '';
    final repoPath = projectPath.isNotEmpty
        ? projectPath
        : cubit.state.repoPath;
    await removeWorktreeWithSessions(
      service: service,
      repoPath: repoPath,
      worktreePath: group.worktree!.path,
      worktree: group.worktree,
      options: WorktreeDeleteOptions(
        force: result.force,
        deleteBranch: result.deleteBranch,
        deleteSessions: result.deleteSessions,
      ),
      sessionsInGroup: sessionsInGroup,
      deleteSession: (id) => chatCubit.deleteSession(repo, id),
    );
    await cubit.load(repoPath, force: true);
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: l10n.worktreeDeleteFailed(error.toString()),
      variant: TpToastVariant.error,
    );
  }
}
