import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/workspace.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../services/compose/compose_draft_cache.dart';
import 'workspace_chat_landing.dart';
import 'workspace_landing_skeleton.dart';
import 'workspace_session_actions.dart';

typedef WorkspaceLandingMessageSubmitter =
    Future<bool> Function(
      BuildContext context,
      Workspace workspace, {
      required LandingLaunchContext launch,
      required String message,
      String? workingDirectory,
      String? expertKey,
    });

typedef WorkspaceLandingDraftPersister =
    Future<void> Function(String workspaceId, LandingLaunchContext draft);

typedef WorkspaceLandingDraftCleaner =
    Future<void> Function(String workspaceId);

Future<void> clearWorkspaceLandingDraft(String workspaceId) async {
  await composeDraftCache.clearLandingPersistent(workspaceId);
  composeDraftCache.clearLandingDraft(workspaceId);
}

/// Unbound Chat pane for a workspace — sibling to [ChatPage], not inside the shell.
class WorkspaceChatPane extends StatefulWidget {
  const WorkspaceChatPane({
    required this.workspace,
    this.initialText,
    this.initialTextRevision = 0,
    this.submitter = submitWorkspaceLandingMessage,
    this.landingDraftPersister = persistLandingDraft,
    this.landingDraftCleaner = clearWorkspaceLandingDraft,
    super.key,
  });

  final Workspace workspace;
  final String? initialText;
  final int initialTextRevision;
  final WorkspaceLandingMessageSubmitter submitter;
  final WorkspaceLandingDraftPersister landingDraftPersister;
  final WorkspaceLandingDraftCleaner landingDraftCleaner;

  @override
  State<WorkspaceChatPane> createState() => _WorkspaceChatPaneState();
}

class _WorkspaceChatPaneState extends State<WorkspaceChatPane> {
  /// Re-entrancy guard only — never drives UI. Visible launch progress comes
  /// from the active pod's phase (session-scoped), not this pane-global bool.
  bool _submitInFlight = false;

  Workspace _workspaceForSubmit(BuildContext context) {
    final id = widget.workspace.workspaceId;
    return context.read<ChatCubit>().state.workspaces.firstWhere(
      (w) => w.workspaceId == id,
      orElse: () => widget.workspace,
    );
  }

  Future<void> _submit(String message, LandingLaunchContext draft) async {
    if (_submitInFlight) return;
    _submitInFlight = true;
    try {
      final workspace = _workspaceForSubmit(context);
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

      await widget.landingDraftPersister(workspace.workspaceId, draft);
      if (!mounted) return;

      final delivered = await widget.submitter(
        context,
        workspace,
        launch: draft,
        message: message,
        workingDirectory: workingDirectory,
        expertKey: draft.expertKey,
      );
      if (delivered) {
        await widget.landingDraftCleaner(workspace.workspaceId);
      }
    } finally {
      _submitInFlight = false;
    }
  }

  /// Whether the active session is still launching. Scoped to that session's
  /// pod — it never blocks the rest of the pane or other conversations.
  bool _launchInFlight(BuildContext context) => context.select<ChatCubit, bool>(
    (c) => c.activePod?.phase.isLaunching ?? false,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workspace = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (w) => w.workspaceId == widget.workspace.workspaceId,
        orElse: () => widget.workspace,
      ),
    );
    final launching = _launchInFlight(context);
    return SizedBox.expand(
      child: ColoredBox(
        color: cs.surface,
        key: AppKeys.chatWorkspace,
        // The landing always stays mounted and interactive; `launching` only
        // drives the scoped compose progress, never a full-pane replacement.
        child: TpDeferredMountShell(
          delayFrames: 2,
          awaitIdle: false,
          placeholder: const WorkspaceLandingSkeleton(),
          child: WorkspaceChatLanding(
            workspace: workspace,
            initialText: widget.initialText,
            initialTextRevision: widget.initialTextRevision,
            isSubmitting: launching,
            onSubmit: (message, draft) => unawaited(_submit(message, draft)),
          ),
        ),
      ),
    );
  }
}
