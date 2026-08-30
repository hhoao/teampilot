import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../utils/ui/app_keys.dart';
import '../../cubits/chat/session_launch_retry.dart';
import 'package:shared_ui/shared_ui.dart';
import 'session_seat_working.dart';

/// Floating capsule in the chat page's top-right corner that switches a
/// session between Chat and Terminal.
class SessionWorkbenchViewToggle extends StatelessWidget {
  const SessionWorkbenchViewToggle({
    required this.workspaceId,
    required this.sessionId,
    super.key,
  });

  final String workspaceId;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final view = seatSelect<ChatCubit, SessionWorkbenchView>(context, (c) {
      // The pod is the canonical view source (same read as the workbench
      // body); fall back to the tab during the thin-ChatCubit transition.
      final podView = c.podFor(sessionId)?.view;
      if (podView != null) return podView;
      final tab = c.tabStore.openTabBySessionId(sessionId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    });
    final showingChat = view == SessionWorkbenchView.chat;
    final l10n = context.l10n;

    return TpSegmentedControl(
      key: AppKeys.sessionWorkbenchViewToggle,
      totalSwitches: 2,
      initialLabelIndex: showingChat ? 0 : 1,
      labels: [
        l10n.sessionWorkbenchViewChat,
        l10n.sessionWorkbenchViewTerminal,
      ],
      icons: const [Icons.chat_bubble_outline_rounded, Icons.terminal_rounded],
      onToggle: (index) {
        if (index == null || index == (showingChat ? 0 : 1)) return;
        unawaited(_toggle(context, showingChat: showingChat));
      },
    );
  }

  Future<void> _toggle(
    BuildContext context, {
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
