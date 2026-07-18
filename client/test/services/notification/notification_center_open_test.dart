import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_notification.dart';
import 'package:teampilot/services/notification/notification_center_open.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('openNotificationCenterItem marks read and navigates payload', () async {
    final marked = <String>[];
    final navigated = <String>[];
    final notification = AppNotification(
      id: 'n1',
      variant: TpToastVariant.success,
      title: 'Session',
      message: 'Ready',
      createdAt: DateTime(2026, 7, 19),
      payload: '/home-v2/workspace/w1?session=s1',
    );

    await openNotificationCenterItem(
      notification: notification,
      markRead: (id) async => marked.add(id),
      go: navigated.add,
    );

    expect(marked, ['n1']);
    expect(navigated, ['/home-v2/workspace/w1?session=s1']);
  });

  test('openNotificationCenterItem marks read without navigate when no payload',
      () async {
    final marked = <String>[];
    final navigated = <String>[];
    final notification = AppNotification(
      id: 'n2',
      variant: TpToastVariant.error,
      message: 'Failed',
      createdAt: DateTime(2026, 7, 19),
    );

    await openNotificationCenterItem(
      notification: notification,
      markRead: (id) async => marked.add(id),
      go: navigated.add,
    );

    expect(marked, ['n2']);
    expect(navigated, isEmpty);
  });

  test('openNotificationCenterItem marks read without navigate for non-workspace',
      () async {
    final marked = <String>[];
    final navigated = <String>[];
    final notification = AppNotification(
      id: 'n3',
      variant: TpToastVariant.warning,
      message: 'Warn',
      createdAt: DateTime(2026, 7, 19),
      payload: '/config/layout',
    );

    await openNotificationCenterItem(
      notification: notification,
      markRead: (id) async => marked.add(id),
      go: navigated.add,
    );

    expect(marked, ['n3']);
    expect(navigated, isEmpty);
  });
}
