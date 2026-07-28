import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/worktree_cubit.dart';
import '../../models/landing_launch_context.dart';
import '../../models/workspace.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing.dart';
import '../../pages/home_workspace/workspace/workspace_session_actions.dart';
import '../../utils/logging/logger_utils.dart';
import '../../utils/workspace/landing_draft_resolver.dart';
import 'selection_ai_context.dart';

abstract final class SelectionAskAi {
  static Future<void> openComposeDialog(
    BuildContext context, {
    required String aiContext,
    required Workspace workspace,
    required String tabScopeId,
  }) async {
    final prefill = selectionAskAiPrefillText(aiContext);
    if (prefill.isEmpty) return;

    WorktreeCubit worktreeCubit;
    try {
      // The dialog route is above WorkspaceSplitPane's provider scope, so
      // capture the workspace-scoped cubit before crossing the route boundary.
      worktreeCubit = context.read<WorktreeCubit>();
    } on ProviderNotFoundException catch (error, stackTrace) {
      AppLogger.instance.w(
        'Selection Ask AI requires a workspace WorktreeCubit; dialog not opened',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    final chat = context.read<ChatCubit>();
    if (chat.tabStore.activeWorkspaceId != tabScopeId) {
      chat.setActiveWorkspace(tabScopeId);
    }

    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<WorktreeCubit>.value(
        value: worktreeCubit,
        child: _SelectionAskAiDialog(
          workspace: workspace,
          initialText: prefill,
        ),
      ),
    );
  }
}

class _SelectionAskAiDialog extends StatefulWidget {
  const _SelectionAskAiDialog({
    required this.workspace,
    required this.initialText,
  });

  final Workspace workspace;
  final String initialText;

  @override
  State<_SelectionAskAiDialog> createState() => _SelectionAskAiDialogState();
}

class _SelectionAskAiDialogState extends State<_SelectionAskAiDialog> {
  var _submitting = false;

  Workspace _workspaceForSubmit() {
    final id = widget.workspace.workspaceId;
    return context.read<ChatCubit>().state.workspaces.firstWhere(
      (workspace) => workspace.workspaceId == id,
      orElse: () => widget.workspace,
    );
  }

  Future<void> _submit(String message, LandingLaunchContext draft) async {
    if (_submitting || message.trim().isEmpty) return;

    setState(() => _submitting = true);
    try {
      final workspace = _workspaceForSubmit();
      String? workingDirectory;
      final draftPath = draft.workingDirectoryPath?.trim();
      if (draftPath != null && draftPath.isNotEmpty) {
        workingDirectory = draftPath;
      } else {
        try {
          workingDirectory = context
              .read<WorktreeCubit>()
              .state
              .pathForNewSession;
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

      if (!mounted) return;
      // Delivery (connect + inject) keeps running on captured cubits after the
      // dialog closes, exactly like the Chat landing pane which unmounts here.
      await submitWorkspaceLandingMessage(
        context,
        workspace,
        launch: draft,
        message: message,
        workingDirectory: workingDirectory,
        expertKey: draft.expertKey,
        onSessionOpened: (_) {
          if (mounted) Navigator.of(context).pop();
        },
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    return TpDialog(
      maxWidth: 880,
      scrollable: true,
      contentPadding: EdgeInsets.all(spacing.md),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          WorkspaceChatLanding(
            workspace: widget.workspace,
            initialText: widget.initialText,
            isSubmitting: _submitting,
            showLandingChrome: false,
            onSubmit: (message, draft) => unawaited(_submit(message, draft)),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: TpIconButton(
              key: const Key('selection-ask-ai-dismiss'),
              icon: Icons.close_rounded,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              backgroundColor: Colors.transparent,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
