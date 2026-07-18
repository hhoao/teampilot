import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/repositories/notification_repository.dart';
import 'package:shared_ui/shared_ui.dart';

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

Future<void> _waitForItemCount(NotificationCubit cubit, int count) async {
  if (cubit.state.items.length >= count) return;
  await cubit.stream.firstWhere((state) => state.items.length >= count);
}

void main() {
  test('record adds unread notification for success', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'Done', variant: TpToastVariant.success);
    await _waitForItemCount(cubit, 1);

    expect(cubit.state.unreadCount, 1);
    expect(cubit.state.items.single.message, 'Done');
  });

  test('record ignores info variant', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'FYI', variant: TpToastVariant.info);
    await pumpEventQueue();

    expect(cubit.state.items, isEmpty);
    expect(cubit.state.unreadCount, 0);
  });

  test('markAllRead clears unread count', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'Done', variant: TpToastVariant.success);
    await _waitForItemCount(cubit, 1);
    await cubit.markAllRead();

    expect(cubit.state.unreadCount, 0);
    expect(cubit.state.items.single.isRead, isTrue);
  });

  test('markRead clears unread for one item', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(message: 'Done', variant: TpToastVariant.success);
    await _waitForItemCount(cubit, 1);
    final id = cubit.state.items.single.id;
    await cubit.markRead(id);

    expect(cubit.state.unreadCount, 0);
    expect(cubit.state.items.single.isRead, isTrue);
  });

  test('record stores payload for session deep links', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(
      message: 'Ready',
      variant: TpToastVariant.success,
      title: 'Fix login',
      payload: '/home-v2/workspace/w1?session=s1',
    );
    await _waitForItemCount(cubit, 1);

    expect(
      cubit.state.items.single.payload,
      '/home-v2/workspace/w1?session=s1',
    );
  });

  test('markReadMatchingPayload marks all items with that payload', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    cubit.record(
      message: 'Ready',
      variant: TpToastVariant.success,
      payload: '/home-v2/workspace/w1?session=s1',
    );
    cubit.record(
      message: 'Other',
      variant: TpToastVariant.warning,
      payload: '/home-v2/workspace/w1?session=other',
    );
    await _waitForItemCount(cubit, 2);

    await cubit.markReadMatchingPayload('/home-v2/workspace/w1?session=s1');

    expect(
      cubit.state.items
          .firstWhere((e) => e.payload.endsWith('session=s1'))
          .isRead,
      isTrue,
    );
    expect(
      cubit.state.items
          .firstWhere((e) => e.payload.endsWith('session=other'))
          .isRead,
      isFalse,
    );
    expect(cubit.state.unreadCount, 1);
  });
}
