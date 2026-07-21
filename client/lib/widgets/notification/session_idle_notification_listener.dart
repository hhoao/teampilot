import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../router/app_router.dart';
import '../../services/notification/session_idle_notification_service.dart';

/// Watches [ChatState.workingSessionIds] and fires idle notifications on
/// working → idle transitions.
class SessionIdleNotificationListener extends StatefulWidget {
  const SessionIdleNotificationListener({
    required this.child,
    this.service,
    super.key,
  });

  final Widget child;
  final SessionIdleNotificationService? service;

  @override
  State<SessionIdleNotificationListener> createState() =>
      _SessionIdleNotificationListenerState();
}

class _SessionIdleNotificationListenerState
    extends State<SessionIdleNotificationListener> {
  Set<String> _previousWorking = const {};
  late final SessionIdleNotificationService _service =
      widget.service ?? SessionIdleNotificationService();

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) =>
          previous.workingSessionIds != next.workingSessionIds,
      listener: _onWorkingSessionsChanged,
      child: widget.child,
    );
  }

  void _onWorkingSessionsChanged(BuildContext context, ChatState state) {
    final current = state.workingSessionIds;
    final becameIdle = _previousWorking.difference(current);
    _previousWorking = current;
    if (becameIdle.isEmpty) return;

    final l10nContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (l10nContext == null || !l10nContext.mounted) return;
    final l10n = l10nContext.l10n;
    final notifyOnSessionIdle = l10nContext
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .notifyOnSessionIdle;
    unawaited(
      _service.notifySessionsBecameIdle(
        sessionIds: becameIdle,
        sessions: state.sessions,
        openTabSessionIds: {for (final tab in state.tabs) tab.id},
        emptySessionTitle: l10n.defaultNewChatSessionTitle,
        notificationSubtitle: l10n.sessionIdleNotificationSubtitle,
        notificationBadge: l10n.sessionIdleNotificationTitle,
        systemNotificationEnabled: notifyOnSessionIdle,
        activeSessionId: state.activeSessionId,
      ),
    );
  }
}
