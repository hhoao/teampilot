import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/services/notification/desktop_system_notifier.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/notification/session_idle_notification_service.dart';
import 'package:teampilot/theme/app_toast_theme.dart';

class _RecordingNotifier implements NotificationRecorder {
  final messages = <String>[];
  final variants = <AppToastVariant>[];

  @override
  void record({required String message, required AppToastVariant variant}) {
    messages.add(message);
    variants.add(variant);
  }
}

void main() {
  test('notifySessionsBecameIdle records and shows OS notification', () async {
    final recorder = _RecordingNotifier();
    final shown = <({String title, String body})>[];
    final service = SessionIdleNotificationService(
      recorder: recorder,
      desktopNotifier: DesktopSystemNotifier(
        isAppFocused: () async => false,
        show: ({required title, required body}) async =>
            shown.add((title: title, body: body)),
      ),
    );

    await service.notifySessionsBecameIdle(
      sessionIds: {'s1'},
      sessions: [
        AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          display: 'Fix login bug',
          createdAt: 0,
        ),
      ],
      emptySessionTitle: 'New Chat',
      notificationTitle: 'Agent ready',
      bodyForTitle: (title) => '$title is idle',
      activeSessionId: 'other',
    );

    expect(recorder.messages, ['Fix login bug is idle']);
    expect(recorder.variants, [AppToastVariant.success]);
    expect(shown, [(title: 'Agent ready', body: 'Fix login bug is idle')]);
  });

  test('notifySessionsBecameIdle skips OS notification for focused active tab',
      () async {
    final recorder = _RecordingNotifier();
    final shown = <({String title, String body})>[];
    final service = SessionIdleNotificationService(
      recorder: recorder,
      desktopNotifier: DesktopSystemNotifier(
        isAppFocused: () async => true,
        show: ({required title, required body}) async =>
            shown.add((title: title, body: body)),
      ),
    );

    await service.notifySessionsBecameIdle(
      sessionIds: {'s1'},
      sessions: [
        AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          createdAt: 0,
        ),
      ],
      emptySessionTitle: 'New Chat',
      notificationTitle: 'Agent ready',
      bodyForTitle: (title) => '$title is idle',
      activeSessionId: 's1',
    );

    expect(recorder.messages, ['New Chat is idle']);
    expect(shown, isEmpty);
  });

  test('notifySessionsBecameIdle ignores closed sessions', () async {
    final recorder = _RecordingNotifier();
    final service = SessionIdleNotificationService(
      recorder: recorder,
      desktopNotifier: DesktopSystemNotifier(
        isAppFocused: () async => false,
        show: ({required title, required body}) async {},
      ),
    );

    await service.notifySessionsBecameIdle(
      sessionIds: {'gone'},
      sessions: const [],
      emptySessionTitle: 'New Chat',
      notificationTitle: 'Agent ready',
      bodyForTitle: (title) => title,
    );

    expect(recorder.messages, isEmpty);
  });
}
