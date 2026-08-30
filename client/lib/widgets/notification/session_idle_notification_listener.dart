import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../router/app_router.dart';
import '../../services/notification/session_idle_notification_service.dart';
import '../../services/notification/session_idle_notify_gate.dart';

/// Watches [ChatState.sessionActivities] and fires idle notifications when
/// [SessionActivity.isReadyToChat] becomes true.
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
  late final SessionIdleNotificationService _service =
      widget.service ?? SessionIdleNotificationService();
  late final SessionIdleNotifyGate _gate = SessionIdleNotifyGate(
    onIdleConfirmed: _onIdleConfirmed,
  );

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) =>
          previous.sessionActivities != next.sessionActivities,
      listener: _onWorkingSessionsChanged,
      child: widget.child,
    );
  }

  void _onWorkingSessionsChanged(BuildContext context, ChatState state) {
    _gate.handle(state.sessionActivities);
  }

  void _onIdleConfirmed(Set<String> sessionIds) {
    if (!mounted) return;
    final l10nContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (l10nContext == null || !l10nContext.mounted) return;
    final l10n = l10nContext.l10n;
    final chat = context.read<ChatCubit>();
    for (final id in sessionIds) {
      chat.acknowledgeSessionReady(id);
    }
    final notifyOnSessionIdle = l10nContext
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .notifyOnSessionIdle;
    unawaited(
      _service.notifySessionsBecameIdle(
        sessionIds: sessionIds,
        sessions: chat.state.sessions,
        openTabSessionIds: {
          for (final tab in chat.tabStore.openTabs) tab.info.id,
        },
        emptySessionTitle: l10n.defaultNewChatSessionTitle,
        notificationSubtitle: l10n.sessionIdleNotificationSubtitle,
        notificationBadge: l10n.sessionIdleNotificationTitle,
        systemNotificationEnabled: notifyOnSessionIdle,
        activeSessionId: chat.activeTab?.info.id,
      ),
    );
  }
}
