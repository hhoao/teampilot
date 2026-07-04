import '../../models/app_session.dart';
import '../../theme/app_toast_theme.dart';
import '../../utils/logger.dart';
import 'desktop_system_notifier.dart';
import 'notification_recorder.dart';

/// Notifies when a session leaves the working set (agent turn finished).
class SessionIdleNotificationService {
  SessionIdleNotificationService({
    DesktopSystemNotifier? desktopNotifier,
    NotificationRecorder? recorder,
  })  : _desktop = desktopNotifier ?? DesktopSystemNotifier.instance,
        _recorder = recorder ?? NotificationRecorder.maybeCurrent;

  final DesktopSystemNotifier _desktop;
  final NotificationRecorder? _recorder;

  Future<void> notifySessionsBecameIdle({
    required Iterable<String> sessionIds,
    required List<AppSession> sessions,
    required String emptySessionTitle,
    required String notificationSubtitle,
    required String notificationBadge,
    bool systemNotificationEnabled = true,
  }) async {
    final ids = sessionIds.toList();
    if (ids.isEmpty) return;

    for (final sessionId in ids) {
      AppSession? session;
      for (final candidate in sessions) {
        if (candidate.sessionId == sessionId) {
          session = candidate;
          break;
        }
      }
      if (session == null) continue;

      final sessionTitle = session.resolveDisplayTitle(emptySessionTitle);

      _recorder?.record(
        title: sessionTitle,
        message: notificationSubtitle,
        variant: AppToastVariant.success,
      );

      if (!systemNotificationEnabled) continue;

      try {
        await _desktop.showNotification(
          title: sessionTitle,
          body: notificationSubtitle,
          subtitle: notificationBadge,
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
