import '../../models/app_notification.dart';

/// Opens an in-app notification-center row: mark read, then deep-link if any.
Future<void> openNotificationCenterItem({
  required AppNotification notification,
  required Future<void> Function(String id) markRead,
  required void Function(String location) go,
}) async {
  await markRead(notification.id);
  final location = notification.payload.trim();
  if (location.isEmpty) return;
  if (!location.startsWith('/home-v2/workspace/')) return;
  go(location);
}
