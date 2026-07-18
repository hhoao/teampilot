import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/notification_repository.dart';
import 'package:shared_ui/shared_ui.dart';

import '../support/in_memory_filesystem.dart';

NotificationRepository _repo(
  InMemoryFilesystem fs, {
  DateTime Function()? clock,
}) => NotificationRepository(
  fs: fs,
  storePath: '/root/notifications.json',
  clock: clock,
);

void main() {
  test('load returns empty store when file absent', () async {
    final repo = _repo(InMemoryFilesystem());
    final store = await repo.load();
    expect(store.items, isEmpty);
  });

  test('append persists success notification', () async {
    final fs = InMemoryFilesystem();
    final now = DateTime(2026, 6, 13, 12);
    final repo = _repo(fs, clock: () => now);
    await repo.append(
      id: 'n1',
      message: 'Saved',
      variant: TpToastVariant.success,
    );

    final fresh = _repo(fs);
    final store = await fresh.load(forceReload: true);
    expect(store.items, hasLength(1));
    expect(store.items.first.message, 'Saved');
    expect(store.items.first.variant, TpToastVariant.success);
    expect(store.items.first.isRead, isFalse);
  });

  test('append persists optional payload for deep links', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs, clock: () => DateTime(2026, 6, 13, 12));
    await repo.append(
      id: 'n1',
      message: 'Ready',
      variant: TpToastVariant.success,
      title: 'Session',
      payload: '/home-v2/workspace/w1?session=s1',
    );

    final store = await _repo(fs).load(forceReload: true);
    expect(store.items.single.payload, '/home-v2/workspace/w1?session=s1');
    expect(store.items.single.title, 'Session');
  });

  test('append skips info variant', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.append(id: 'n1', message: 'FYI', variant: TpToastVariant.info);
    expect((await repo.load()).items, isEmpty);
  });

  test('prunes items older than seven days', () async {
    final fs = InMemoryFilesystem();
    final now = DateTime(2026, 6, 13, 12);
    final repo = _repo(fs, clock: () => now);
    await repo.append(
      id: 'old',
      message: 'stale',
      variant: TpToastVariant.warning,
    );

    final later = now.add(const Duration(days: 8));
    final pruned = _repo(fs, clock: () => later);
    await pruned.append(
      id: 'new',
      message: 'fresh',
      variant: TpToastVariant.error,
    );

    final store = await pruned.load(forceReload: true);
    expect(store.items, hasLength(1));
    expect(store.items.first.id, 'new');
  });

  test('prunes to fifty items', () async {
    final fs = InMemoryFilesystem();
    final now = DateTime(2026, 6, 13, 12);
    final repo = _repo(fs, clock: () => now);
    for (var i = 0; i < 55; i++) {
      await repo.append(
        id: 'n$i',
        message: 'msg $i',
        variant: TpToastVariant.success,
      );
    }
    expect((await repo.load()).items.length, notificationMaxItems);
  });

  test('markRead markAllRead delete clearAll', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.append(
      id: 'a',
      message: 'one',
      variant: TpToastVariant.success,
    );
    await repo.append(id: 'b', message: 'two', variant: TpToastVariant.error);

    await repo.markRead('a');
    expect(
      (await repo.load()).items.firstWhere((e) => e.id == 'a').isRead,
      isTrue,
    );

    await repo.markAllRead();
    expect((await repo.load()).items.every((e) => e.isRead), isTrue);

    await repo.delete('a');
    expect((await repo.load()).items.map((e) => e.id), ['b']);

    await repo.clearAll();
    expect((await repo.load()).items, isEmpty);
  });

  test('markReadMatchingPayload marks matching unread items', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.append(
      id: 'a',
      message: 'one',
      variant: TpToastVariant.success,
      payload: '/home-v2/workspace/w1?session=s1',
    );
    await repo.append(
      id: 'b',
      message: 'two',
      variant: TpToastVariant.success,
      payload: '/home-v2/workspace/w1?session=s2',
    );

    await repo.markReadMatchingPayload('/home-v2/workspace/w1?session=s1');
    final store = await repo.load();
    expect(store.items.firstWhere((e) => e.id == 'a').isRead, isTrue);
    expect(store.items.firstWhere((e) => e.id == 'b').isRead, isFalse);
  });
}
