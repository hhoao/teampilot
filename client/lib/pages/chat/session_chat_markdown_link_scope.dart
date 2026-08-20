import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../services/workbench/session_member_filesystem.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workbench/workspace_href_handler.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/app_toast/app_toast.dart';

/// Holds one [AiMarkdownLinkActions] for the session thread so chat rebuilds
/// do not notify every [AiTextPartView] that depends on the inherited scope.
class SessionChatMarkdownLinkScope extends StatefulWidget {
  const SessionChatMarkdownLinkScope({
    required this.session,
    required this.workspace,
    required this.selectedMemberId,
    required this.hrefRoots,
    required this.child,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String selectedMemberId;
  final List<String> hrefRoots;
  final Widget child;

  @override
  State<SessionChatMarkdownLinkScope> createState() =>
      _SessionChatMarkdownLinkScopeState();
}

class _SessionChatMarkdownLinkScopeState
    extends State<SessionChatMarkdownLinkScope> {
  late final AiMarkdownLinkActions _actions = AiMarkdownLinkActions(
    onLinkTap: _onLinkTap,
  );

  Future<void> _onLinkTap(String href) async {
    try {
      final launchContext = WorkspaceLaunchContext(
        session: widget.session,
        workspace: widget.workspace,
      );
      final fs = await resolveSessionMemberFilesystem(
        lifecycle: context.read<ChatCubit>().lifecycle,
        launchContext: launchContext,
        memberId: widget.selectedMemberId,
        toolsScope: WorkspaceToolsScope.maybeOf(context),
      );
      if (!mounted) return;
      final outcome = await WorkspaceHrefHandler(
        opener: context.read<WorkbenchEditorOpener>(),
      ).open(
        href: href,
        workspaceId: widget.session.workspaceId,
        workspaceRoots: widget.hrefRoots,
        searchBases: widget.hrefRoots,
        fs: fs,
      );
      if (!mounted) return;
      switch (outcome) {
        case WorkspaceHrefOpenOutcome.missing:
        case WorkspaceHrefOpenOutcome.outsideWorkspace:
        case WorkspaceHrefOpenOutcome.notOpenable:
          AppToast.show(
            context,
            message: context.l10n.aiToolFileNotFound(href),
            variant: TpToastVariant.warning,
          );
          break;
        case WorkspaceHrefOpenOutcome.openedExternal:
        case WorkspaceHrefOpenOutcome.openedFile:
        case WorkspaceHrefOpenOutcome.ignored:
          break;
      }
    } on Object catch (error, stackTrace) {
      AppLogger.instance.e(
        'Session chat markdown link open failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AiMarkdownLinkActionsScope(
      actions: _actions,
      child: widget.child,
    );
  }
}
