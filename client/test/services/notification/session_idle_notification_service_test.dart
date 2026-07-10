import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/services/notification/desktop_system_notifier.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/notification/session_idle_notification_service.dart';
import 'package:teampilot/theme/app_toast_theme.dart';

class _RecordingNotifier implements NotificationRecorder {
  final titles = <String>[];
  final messages = <String>[];
  final variants = <AppToastVariant>[];

  @override
  void record({
    required String message,
    required AppToastVariant variant,
    String title = '',
  }) {
    titles.add(title);
    messages.add(message);
    variants.add(variant);
  }
}

typedef _Shown = ({
  String title,
  String body,
  String? subtitle,
  String? payload,
});

void main() {
  test('notifySessionsBecameIdle records and shows OS notification', () async {
    final recorder = _RecordingNotifier();
    final shown = <_Shown>[];
    final service = SessionIdleNotificationService(
      recorder: recorder,
      desktopNotifier: DesktopSystemNotifier(
        show: ({required title, required body, subtitle, payload}) async =>
            shown.add((
              title: title,
              body: body,
              subtitle: subtitle,
              payload: payload,
            )),
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
      notificationSubtitle: 'Ready for your next message',
      notificationBadge: 'Agent ready',
    );

    expect(recorder.titles, ['Fix login bug']);
    expect(recorder.messages, ['Ready for your next message']);
    expect(recorder.variants, [AppToastVariant.success]);
    expect(shown, [
      (
        title: 'Fix login bug',
        body: 'Ready for your next message',
        subtitle: 'Agent ready',
        payload: '/home-v2/workspace/w1?session=s1',
      ),
    ]);
  });

  test(
    'notifySessionsBecameIdle always shows OS notification even when focused',
    () async {
      final recorder = _RecordingNotifier();
      final shown = <_Shown>[];
      final service = SessionIdleNotificationService(
        recorder: recorder,
        desktopNotifier: DesktopSystemNotifier(
          show: ({required title, required body, subtitle, payload}) async =>
              shown.add((
                title: title,
                body: body,
                subtitle: subtitle,
                payload: payload,
              )),
        ),
      );

      await service.notifySessionsBecameIdle(
        sessionIds: {'s1'},
        sessions: [
          AppSession(sessionId: 's1', workspaceId: 'w1', createdAt: 0),
        ],
        emptySessionTitle: 'New Chat',
        notificationSubtitle: 'Ready for your next message',
        notificationBadge: 'Agent ready',
      );

      expect(recorder.titles, ['New Chat']);
      expect(recorder.messages, ['Ready for your next message']);
      expect(shown, hasLength(1));
      expect(shown.single.payload, '/home-v2/workspace/w1?session=s1');
    },
  );

  test(
    'notifySessionsBecameIdle skips OS notification when disabled',
    () async {
      final recorder = _RecordingNotifier();
      final shown = <_Shown>[];
      final service = SessionIdleNotificationService(
        recorder: recorder,
        desktopNotifier: DesktopSystemNotifier(
          show: ({required title, required body, subtitle, payload}) async =>
              shown.add((
                title: title,
                body: body,
                subtitle: subtitle,
                payload: payload,
              )),
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
        notificationSubtitle: 'Ready for your next message',
        notificationBadge: 'Agent ready',
        systemNotificationEnabled: false,
      );

      expect(recorder.titles, ['Fix login bug']);
      expect(recorder.messages, ['Ready for your next message']);
      expect(shown, isEmpty);
    },
  );

  test('notifySessionsBecameIdle ignores closed sessions', () async {
    final recorder = _RecordingNotifier();
    final service = SessionIdleNotificationService(
      recorder: recorder,
      desktopNotifier: DesktopSystemNotifier(
        show: ({required title, required body, subtitle, payload}) async {},
      ),
    );

    await service.notifySessionsBecameIdle(
      sessionIds: {'gone'},
      sessions: const [],
      emptySessionTitle: 'New Chat',
      notificationSubtitle: 'Ready',
      notificationBadge: 'Agent ready',
    );

    expect(recorder.messages, isEmpty);
  });
}
