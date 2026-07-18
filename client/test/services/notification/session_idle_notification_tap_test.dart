import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/session_idle_notification_tap.dart';

void main() {
  test('handleSessionIdleNotificationTap navigates valid workspace payload',
      () async {
    final navigated = <String>[];
    final marked = <String>[];
    var focused = false;

    await handleSessionIdleNotificationTap(
      payload: '/home-v2/workspace/ws-1?session=sess-1',
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );

    expect(focused, isTrue);
    expect(navigated, ['/home-v2/workspace/ws-1?session=sess-1']);
    expect(marked, ['/home-v2/workspace/ws-1?session=sess-1']);
  });

  test('handleSessionIdleNotificationTap ignores empty or non-workspace payload',
      () async {
    final navigated = <String>[];
    final marked = <String>[];
    var focused = false;

    await handleSessionIdleNotificationTap(
      payload: null,
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );
    await handleSessionIdleNotificationTap(
      payload: '  ',
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );
    await handleSessionIdleNotificationTap(
      payload: '/config/layout',
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );

    expect(focused, isFalse);
    expect(navigated, isEmpty);
    expect(marked, isEmpty);
  });
}
