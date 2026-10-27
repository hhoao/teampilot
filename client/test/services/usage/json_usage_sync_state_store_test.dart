import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage_sync_state.dart';
import 'package:teampilot/services/usage/json_usage_sync_state_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('round-trips sync state', () async {
    final fs = InMemoryFilesystem();
    final store = JsonUsageSyncStateStore(
      fs: fs,
      filePath: '/tp/usage/sync_state.json',
    );

    await store.save(
      const UsageSyncState(lastFullScanAtMs: 100, lastSyncAtMs: 200),
    );
    final loaded = await store.load();

    expect(loaded.hasBaseline, isTrue);
    expect(loaded.lastFullScanAtMs, 100);
    expect(loaded.lastSyncAtMs, 200);
  });

  test('corrupt state falls back to empty', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/tp/usage/sync_state.json', '{bad');
    final store = JsonUsageSyncStateStore(
      fs: fs,
      filePath: '/tp/usage/sync_state.json',
    );

    final loaded = await store.load();

    expect(loaded.hasBaseline, isFalse);
    expect(loaded.lastSyncAtMs, isNull);
  });
}
