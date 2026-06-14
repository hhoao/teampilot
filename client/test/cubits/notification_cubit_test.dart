import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/repositories/notification_repository.dart';
import 'package:teampilot/theme/app_toast_theme.dart';

import '../support/in_memory_filesystem.dart';

NotificationCubit _cubit() {
  final fs = InMemoryFilesystem();
  return NotificationCubit(
    repository: NotificationRepository(
      fs: fs,
      storePath: '/root/notifications.json',
      clock: () => DateTime(2026, 6, 13, 12),
    ),
  );
}

void main() {
  test('record adds unread notification for success', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'Done', variant: AppToastVariant.success);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.unreadCount, 1);
    expect(cubit.state.items.single.message, 'Done');
  });

  test('record ignores info variant', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'FYI', variant: AppToastVariant.info);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.items, isEmpty);
    expect(cubit.state.unreadCount, 0);
  });

  test('markAllRead clears unread count', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'Done', variant: AppToastVariant.success);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await cubit.markAllRead();

    expect(cubit.state.unreadCount, 0);
    expect(cubit.state.items.single.isRead, isTrue);
  });
}
