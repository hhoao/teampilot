import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/repo_clone_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/app_toast/app_toast.dart';

/// What the user picked in the clone-completion dialog.
enum CloneCompletionAction { newWorkspace, addToWorkspace }

/// Presents the new-vs-add choice for a succeeded clone ([RepoCloneCubit]
/// appends it to `state.pendingChoice`).
///
/// Wiring mirrors [showHomeNewWorkspaceDialog]: the real cubit/repository
/// calls live here so the dialog widgets stay pure and testable. Every exit
/// path (new workspace, add to existing, dismiss) calls
/// [RepoCloneCubit.dismissChoice] exactly once so the next pending choice can
/// surface.
Future<void> showCloneCompletedDialog(
  BuildContext context, {
  required RepoCloneTask task,
}) async {
  // Hoisted before the first await: safe against async-gap context use and
  // against the shell unmounting while a dialog is open.
  final repoCloneCubit = context.read<RepoCloneCubit>();
  final chatCubit = context.read<ChatCubit>();
  final sessionRepository = context.read<SessionRepository>();
  final identityRepository = context.read<LaunchProfileRepository>();
  final action = await showDialog<CloneCompletionAction>(
    context: context,
    builder: (_) => CloneCompletedDialog(task: task),
  );
  try {
    switch (action) {
      case CloneCompletionAction.newWorkspace:
        final workspaceId = await chatCubit.createWorkspaceWithFirstSession(
          [WorkspaceFolder(path: task.destPath, targetId: task.targetId)],
          sessionRepository,
          sessionTeamId: '',
          display: task.dirName,
          allowDuplicate: true,
          identityRepository: identityRepository,
        );
        if (context.mounted) context.go('/home-v2/workspace/$workspaceId');
      case CloneCompletionAction.addToWorkspace:
        // The inner picker already performed the add + success toast.
        if (context.mounted) {
          await _showCloneAddToWorkspaceDialog(context, task);
        }
      case null:
        // Dismissed (header close / barrier): plain skip.
        return;
    }
  } catch (error, stackTrace) {
    // The wiring (workspace create / folder add) failed: log it — no
    // generic clone-failure l10n key exists and none may be added here.
    appLogger.e(
      'clone completion wiring failed for task ${task.id} '
      '(${task.destPath})',
      error: error,
      stackTrace: stackTrace,
    );
  } finally {
    // Every exit path — skip return, successful wiring, or a throw — must
    // release the pending choice, or the shell's presentation guard would
    // block every future clone-completion dialog for this session.
    repoCloneCubit.dismissChoice(task.id);
  }
}

Future<void> _showCloneAddToWorkspaceDialog(
  BuildContext context,
  RepoCloneTask task,
) async {
  // Hoisted before awaits; the onAdd closure runs after an async gap.
  final chatCubit = context.read<ChatCubit>();
  final sessionRepository = context.read<SessionRepository>();
  await showDialog<void>(
    context: context,
    builder: (_) => CloneAddToWorkspaceDialog(
      task: task,
      workspaces: chatCubit.state.workspaces,
      onAdd: (workspace) => chatCubit.addWorkspaceDirectory(
        sessionRepository,
        workspace,
        WorkspaceFolder(path: task.destPath, targetId: task.targetId),
      ),
    ),
  );
}

/// "Clone complete" modal: create a workspace from the clone or add the folder
/// to an existing workspace. Pops a [CloneCompletionAction]; a plain dismiss
/// (header close) pops `null` = skip.
class CloneCompletedDialog extends StatelessWidget {
  const CloneCompletedDialog({super.key, required this.task});

  final RepoCloneTask task;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);

    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.cloneRepositoryCompletedTitle),
          const SizedBox(height: 16),
          Text(
            l10n.cloneRepositoryCompletedBody(task.destPath),
            style: styles.mdColored(cs.onSurfaceVariant),
          ),
          TpDialogActions(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(CloneCompletionAction.addToWorkspace),
                child: Text(l10n.cloneRepositoryAddToWorkspace),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(CloneCompletionAction.newWorkspace),
                child: Text(l10n.cloneRepositoryCreateWorkspace),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Choose a workspace" picker shown for the add-to-existing action.
///
/// Pure widget: [workspaces] and [onAdd] are injected; the real
/// [ChatCubit.addWorkspaceDirectory] call is wired in
/// [showCloneCompletedDialog]. On tap: awaits [onAdd], shows the success toast,
/// then pops.
class CloneAddToWorkspaceDialog extends StatefulWidget {
  const CloneAddToWorkspaceDialog({
    super.key,
    required this.task,
    required this.workspaces,
    required this.onAdd,
  });

  final RepoCloneTask task;
  final List<Workspace> workspaces;
  final Future<void> Function(Workspace workspace) onAdd;

  @override
  State<CloneAddToWorkspaceDialog> createState() =>
      _CloneAddToWorkspaceDialogState();
}

class _CloneAddToWorkspaceDialogState extends State<CloneAddToWorkspaceDialog> {
  var _adding = false;

  Future<void> _pick(Workspace workspace) async {
    if (_adding) return;
    setState(() => _adding = true);
    var added = false;
    try {
      await widget.onAdd(workspace);
      added = true;
    } finally {
      // Close the picker regardless of the add outcome so the choice flow
      // always ends; the success toast only fires on a completed add.
      if (mounted) {
        if (added) {
          AppToast.show(
            context,
            message: context.l10n.cloneRepositoryAddToExistingSucceeded(
              widget.task.dirName,
              workspace.effectiveDisplay,
            ),
            variant: TpToastVariant.success,
          );
        }
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 480,
      maxHeight: 420,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.cloneRepositoryChooseWorkspace),
          const SizedBox(height: 8),
          if (widget.workspaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.cloneRepositoryCompletedBody(widget.task.destPath),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final workspace in widget.workspaces)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(workspace.effectiveDisplay),
                subtitle: Text(
                  workspace.firstFolderPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _pick(workspace),
              ),
        ],
      ),
    );
  }
}
