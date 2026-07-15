import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/session_connect_request.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/app_keys.dart';
import '../../utils/team_member_naming.dart';
import 'package:shared_ui/shared_ui.dart';

/// Tab-bar control to switch a session between History and Terminal.
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
      (c) => c.activeTabId(workspaceId),
    );
    if (active == null || active.kind != WorkbenchTabKind.session) {
      return const SizedBox.shrink();
    }
    final sessionId = active.id;
    final view = context.select<ChatCubit, SessionWorkbenchView>((c) {
      final tab = c.tabStore.openTabBySessionId(sessionId);
      return tab?.workbenchView ?? SessionWorkbenchView.history;
    });
    final showingHistory = view == SessionWorkbenchView.history;
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return TpIconButton(
      key: AppKeys.sessionWorkbenchViewToggle,
      icon: showingHistory
          ? Icons.terminal_rounded
          : Icons.history_rounded,
      tooltip: showingHistory
          ? l10n.sessionWorkbenchShowTerminal
          : l10n.sessionWorkbenchShowHistory,
      color: cs.onSurfaceVariant,
      onTap: () => unawaited(
        _toggle(
          context,
          sessionId: sessionId,
          showingHistory: showingHistory,
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context, {
    required String sessionId,
    required bool showingHistory,
  }) async {
    final chat = context.read<ChatCubit>();
    final workbench = context.read<WorkbenchCubit>();
    final tabId = WorkbenchTabId.session(sessionId);

    if (showingHistory) {
      chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal);
      workbench.pinTab(workspaceId, tabId);
      workbench.ensureTab(workspaceId, tabId, preview: false);

      final tab = chat.tabStore.openTabBySessionId(sessionId);
      if (tab == null || tab.isRunning) return;
      if (!context.mounted) return;

      final session = _resolveSession(chat, sessionId);
      if (session == null) return;

      final isPersonal = session.sessionTeam.trim().isEmpty;
      TeamProfile? resolvedTeam = team;
      TeamMemberConfig? member;
      if (!isPersonal) {
        resolvedTeam ??= _teamForSession(context, session);
        if (resolvedTeam != null) {
          final mid = tab.selectedMemberId.trim();
          if (mid.isNotEmpty) {
            member = resolvedTeam.members
                .where((m) => m.id == mid)
                .firstOrNull;
          }
          member ??= resolvedTeam.members
              .where(TeamMemberNaming.isTeamLead)
              .firstOrNull;
          member ??= resolvedTeam.members.firstOrNull;
        }
      }

      await chat.connectWorkspaceSession(
        ExistingSessionConnect(
          session: session,
          team: isPersonal ? null : resolvedTeam,
          member: isPersonal ? null : member,
        ),
      );
      return;
    }

    chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.history);
  }

  AppSession? _resolveSession(ChatCubit chat, String sessionId) {
    for (final s in chat.state.sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return chat.tabStore.openTabBySessionId(sessionId)?.persistedSession;
  }

  TeamProfile? _teamForSession(BuildContext context, AppSession session) {
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return null;
    final profile = context.read<LaunchProfileCubit>().byId(teamId);
    return profile is TeamProfile ? profile : null;
  }
}
