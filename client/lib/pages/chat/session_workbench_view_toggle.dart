import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/ui/app_keys.dart';
import '../../cubits/chat/session_launch_retry.dart';
import 'package:shared_ui/shared_ui.dart';

/// Tab-bar control to switch a session between Chat and Terminal.
class SessionWorkbenchViewToggle extends StatelessWidget {
  const SessionWorkbenchViewToggle({
    required this.workspaceId,
    required this.tabScopeId,
    this.team,
    super.key,
  });

  final String workspaceId;
  final String tabScopeId;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    final active = context.select<WorkbenchCubit, WorkbenchTabId?>(
      (c) => c.centerActiveId(workspaceId),
    );
    if (active == null || active.kind != WorkbenchTabKind.session) {
      return const SizedBox.shrink();
    }
    final sessionId = active.id;
    final view = context.select<ChatCubit, SessionWorkbenchView>((c) {
      // The pod is the canonical view source (same read as the workbench
      // body); fall back to the tab during the thin-ChatCubit transition.
      final podView = c.podFor(sessionId)?.view;
      if (podView != null) return podView;
      final tab = c.tabStore.openTabBySessionId(sessionId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    });
    final showingChat = view == SessionWorkbenchView.chat;
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return TpIconButton(
      key: AppKeys.sessionWorkbenchViewToggle,
      icon: showingChat
          ? Icons.terminal_rounded
          : Icons.chat_bubble_outline_rounded,
      tooltip: showingChat
          ? l10n.sessionWorkbenchShowTerminal
          : l10n.sessionWorkbenchShowChat,
      color: cs.onSurfaceVariant,
      onTap: () => unawaited(
        _toggle(context, sessionId: sessionId, showingChat: showingChat),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context, {
    required String sessionId,
    required bool showingChat,
  }) async {
    final chat = context.read<ChatCubit>();
    final workbench = context.read<WorkbenchCubit>();
    final tabId = WorkbenchTabId.session(sessionId);

    if (showingChat) {
      chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal);
      workbench.pin(workspaceId, tabId);
      workbench.openSession(workspaceId, tabId.id, preview: false);

      final tab = chat.tabStore.openTabBySessionId(sessionId);
      if (tab == null) return;
      // Stopped + launchError: keep scrollback / banner; Retry is explicit.
      if (!shouldConnectStoppedSessionOnTerminalReveal(
        isRunning: tab.isRunning,
        launchError: tab.info.launchError,
      )) {
        return;
      }
      if (!context.mounted) return;

      final session = _resolveSession(chat, sessionId);
      if (session == null) return;

      // Team / mixed sessions: [setSessionWorkbenchView] already called
      // [ensureMemberTerminalForView] for the selected member (lazy resume).
      // A full [connectWorkspaceSession] would reconnect via the mixed-team
      // lead path and optionally auto-launch every roster member — not the
      // per-member restore users expect when revealing Terminal.
      if (session.sessionTeam.trim().isNotEmpty) return;

      final request = buildRetryExistingSessionConnect(
        session: session,
        selectedMemberId: tab.selectedMemberId,
        preserveWorkbenchView: false,
      );
      await chat.connectWorkspaceSession(request!);
      return;
    }

    chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.chat);
  }

  AppSession? _resolveSession(ChatCubit chat, String sessionId) {
    for (final s in chat.state.sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return chat.tabStore.openTabBySessionId(sessionId)?.persistedSession;
  }

}
