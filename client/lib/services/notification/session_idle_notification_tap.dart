/// Handles OS notification taps for session-idle deep links (hot start only).
Future<void> handleSessionIdleNotificationTap({
  required String? payload,
  required void Function(String location) go,
  Future<void> Function()? focusWindow,
}) async {
  final location = payload?.trim() ?? '';
  if (location.isEmpty) return;
  if (!location.startsWith('/home-v2/workspace/')) return;

  await focusWindow?.call();
  go(location);
}
