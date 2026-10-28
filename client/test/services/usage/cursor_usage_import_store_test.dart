import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_import.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/cursor_usage_import_store.dart';

import '../../support/in_memory_filesystem.dart';

SessionUsageEvent _event(String id, int ts, {int output = 1}) =>
    SessionUsageEvent(
      requestId: id,
      cli: CliTool.cursor,
      model: 'cursor-auto',
      inputTokens: 10,
      outputTokens: output,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: ts,
      sessionId: cursorImportedSessionId,
    );

void main() {
  test(
    'merges manual rows and replaces only the synced account window',
    () async {
      final fs = InMemoryFilesystem();
      final store = CursorUsageImportStore(
        fs: fs,
        filePath: '/tp/usage/cursor_import.json',
      );

      await store.merge(
        events: [_event('manual-1', 100), _event('manual-2', 200)],
        origin: CursorUsageOrigin.manual,
        startMs: 100,
        endMs: 200,
        nowMs: 1,
      );
      expect((await store.status()).eventCount, 2);

      await store.merge(
        events: [_event('sync-1', 300), _event('sync-2', 400)],
        origin: CursorUsageOrigin.sync,
        startMs: 300,
        endMs: 400,
        nowMs: 2,
        account: 'acct',
      );
      expect((await store.status()).eventCount, 4);

      final replaced = await store.merge(
        events: [_event('sync-1', 300, output: 9), _event('sync-3', 350)],
        origin: CursorUsageOrigin.sync,
        startMs: 300,
        endMs: 500,
        nowMs: 3,
        account: 'acct',
      );

      expect(replaced.status.eventCount, 4);
      expect(replaced.status.lastSyncAtMs, 3);
      final events = await store.loadEvents();
      expect(events.map((e) => e.requestId), [
        'manual-1',
        'manual-2',
        'sync-1',
        'sync-3',
      ]);
      expect(events[2].outputTokens, 9);
    },
  );

  test('manual rows win over the same synced request id', () async {
    final fs = InMemoryFilesystem();
    final store = CursorUsageImportStore(
      fs: fs,
      filePath: '/tp/usage/cursor_import.json',
    );
    await store.merge(
      events: [_event('same', 100, output: 1)],
      origin: CursorUsageOrigin.sync,
      startMs: 0,
      endMs: 200,
      nowMs: 1,
      account: 'acct',
    );
    await store.merge(
      events: [_event('same', 100, output: 2)],
      origin: CursorUsageOrigin.manual,
      startMs: 100,
      endMs: 100,
      nowMs: 2,
    );
    await store.merge(
      events: [_event('same', 100, output: 3)],
      origin: CursorUsageOrigin.sync,
      startMs: 0,
      endMs: 200,
      nowMs: 3,
      account: 'acct',
    );

    final events = await store.loadEvents();
    expect(events.single.outputTokens, 2);
  });

  test('clears imported usage', () async {
    final fs = InMemoryFilesystem();
    final store = CursorUsageImportStore(
      fs: fs,
      filePath: '/tp/usage/cursor_import.json',
    );
    await store.merge(
      events: [_event('x', 1)],
      origin: CursorUsageOrigin.manual,
      startMs: 1,
      endMs: 1,
      nowMs: 1,
    );
    await store.clear();
    expect((await store.status()).hasData, isFalse);
    expect(await store.loadEvents(), isEmpty);
  });
}
