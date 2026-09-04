import '../../l10n/app_localizations.dart';
import '../../models/app_session.dart';
import '../../pages/home_workspace/home_workspace_route.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../utils/logging/logger.dart';
import '../../utils/session/session_display_title.dart';
import 'desktop_system_notifier.dart';
import 'notification_recorder.dart';

/// Notifies when a session leaves the working set (agent turn finished).
class SessionIdleNotificationService {
  SessionIdleNotificationService({
    DesktopSystemNotifier? desktopNotifier,
    NotificationRecorder? recorder,
  }) : _desktop = desktopNotifier ?? DesktopSystemNotifier.instance,
       _recorder = recorder ?? NotificationRecorder.maybeCurrent;

  final DesktopSystemNotifier _desktop;
  final NotificationRecorder? _recorder;

  Future<void> notifySessionsBecameIdle({
    required Iterable<String> sessionIds,
    required List<AppSession> sessions,
    required Iterable<String> openTabSessionIds,
    required AppLocalizations l10n,
    required String notificationSubtitle,
    required String notificationBadge,
    bool systemNotificationEnabled = true,
    String? activeSessionId,
  }) async {
    final ids = sessionIds.toList();
    if (ids.isEmpty) return;

    final focused = await _desktop.isAppFocused();

    for (final sessionId in ids) {
      // Closing a working tab also leaves busySessionIds; that is not idle.
      if (!openTabSessionIds.contains(sessionId)) continue;

      AppSession? session;
      for (final candidate in sessions) {
        if (candidate.sessionId == sessionId) {
          session = candidate;
          break;
        }
      }
      if (session == null) continue;

      final sessionTitle = sessionListDisplayTitle(session, l10n);
      final payload = HomeWorkspaceRoute.sessionLocation(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
      );

      // Skip center + OS notify when the user is already looking at this session.
      if (focused && activeSessionId == sessionId) continue;

      _recorder?.record(
        title: sessionTitle,
        message: notificationSubtitle,
        variant: TpToastVariant.success,
        payload: payload,
      );

      if (!systemNotificationEnabled) continue;

      try {
        await _desktop.showNotification(
          title: sessionTitle,
          body: notificationSubtitle,
          subtitle: notificationBadge,
          payload: payload,
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[session-idle-notify] OS notification failed session=$sessionId',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
