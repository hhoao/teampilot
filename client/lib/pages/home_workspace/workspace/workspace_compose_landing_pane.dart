import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/workspace.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../chat/chat_workbench_placeholders.dart';
import 'workspace_chat_landing.dart';
import 'workspace_session_actions.dart';

/// Full main-pane compose landing — sibling to [ChatPage], not inside the shell.
class WorkspaceComposeLandingPane extends StatefulWidget {
  const WorkspaceComposeLandingPane({
    required this.workspace,
    super.key,
  });

  final Workspace workspace;

  @override
  State<WorkspaceComposeLandingPane> createState() =>
      _WorkspaceComposeLandingPaneState();
}

class _WorkspaceComposeLandingPaneState extends State<WorkspaceComposeLandingPane> {
  var _submitting = false;

  Workspace _workspaceForSubmit(BuildContext context) {
    final id = widget.workspace.workspaceId;
    return context.read<ChatCubit>().state.workspaces.firstWhere(
      (w) => w.workspaceId == id,
      orElse: () => widget.workspace,
    );
  }

  Future<void> _submit(String message, LandingLaunchContext draft) async {
    if (_submitting) return;

    setState(() => _submitting = true);
    try {
      final workspace = _workspaceForSubmit(context);
      String? workingDirectory;
      final draftPath = draft.workingDirectoryPath?.trim();
      if (draftPath != null && draftPath.isNotEmpty) {
        workingDirectory = draftPath;
      } else {
        try {
          workingDirectory =
              context.read<WorktreeCubit>().state.pathForNewSession;
        } on ProviderNotFoundException {
          workingDirectory = workspace.firstFolderPath;
        }
      }

      final launchProfiles = context.read<LaunchProfileCubit>();
      if (!draft.isPersonal) {
        final teamId = draft.teamId?.trim() ?? '';
        if (teamId.isNotEmpty) {
          await launchProfiles.selectTeam(teamId, silent: true);
        }
      }

      await persistLandingDraft(workspace.workspaceId, draft);

      await submitWorkspaceLandingMessage(
        context,
        workspace,
        launch: draft,
        message: message,
        workingDirectory: workingDirectory,
        expertKey: draft.expertKey,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workspace = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (w) => w.workspaceId == widget.workspace.workspaceId,
        orElse: () => widget.workspace,
      ),
    );
    return SizedBox.expand(
      child: ColoredBox(
        color: cs.surface,
        key: AppKeys.chatWorkspace,
        child: _submitting
            ? ChatWorkbenchSessionLoadingView(
                message: context.l10n.sessionStarting,
              )
            : WorkspaceChatLanding(
                workspace: workspace,
                isSubmitting: _submitting,
                onSubmit: (message, draft) => unawaited(_submit(message, draft)),
              ),
      ),
    );
  }
}
