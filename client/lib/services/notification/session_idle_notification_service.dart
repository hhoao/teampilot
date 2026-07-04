import '../../models/app_session.dart';
import '../../theme/app_toast_theme.dart';
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
    required String notificationTitle,
    required String Function(String sessionTitle) bodyForTitle,
    String? activeSessionId,
  }) async {
    final ids = sessionIds.toList();
    if (ids.isEmpty) return;

    final focused = await _desktop.isAppFocused();

    for (final sessionId in ids) {
      AppSession? session;
      for (final candidate in sessions) {
        if (candidate.sessionId == sessionId) {
          session = candidate;
          break;
        }
      }
      if (session == null) continue;

      final title = session.resolveDisplayTitle(emptySessionTitle);
      final message = bodyForTitle(title);

      _recorder?.record(message: message, variant: AppToastVariant.success);

      // Skip OS toast when the user is already looking at this session.
      if (focused && activeSessionId == sessionId) continue;

      await _desktop.showNotification(title: notificationTitle, body: message);
    }
  }
}
