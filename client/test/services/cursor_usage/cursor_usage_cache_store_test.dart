import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_cache_store.dart';

import '../../support/in_memory_filesystem.dart';

int ms(int day) => DateTime(2026, 10, day).millisecondsSinceEpoch;

void main() {
  late InMemoryFilesystem fs;
  late CursorUsageCacheStore store;
  String pathFor(String accountId) => '/tp/cursor_usage/$accountId.json';

  setUp(() {
    fs = InMemoryFilesystem();
    store = CursorUsageCacheStore(fs: fs, pathFor: pathFor);
  });

  test(
    'load of a missing file returns an empty cache for the account',
    () async {
      expect(
        await store.load('acct1'),
        const CursorUsageCache(accountId: 'acct1'),
      );
    },
  );

  test(
    'load of a corrupt file returns an empty cache for the account',
    () async {
      fs.files[pathFor('acct1')] = '{not json';

      expect(
        await store.load('acct1'),
        const CursorUsageCache(accountId: 'acct1'),
      );
    },
  );

  test(
    'load keys the cache by the requested account, not the payload',
    () async {
      fs.files[pathFor('acct1')] =
          '{"accountId":"other","days":[{"dayMs":${ms(1)},"inputTokens":7}]}';

      final cache = await store.load('acct1');

      expect(cache.accountId, 'acct1');
      expect(cache.days.single.inputTokens, 7);
    },
  );

  test('save then load round-trips days and coverage', () async {
    final cache = CursorUsageCache(
      accountId: 'acct1',
      owningUser: 'user-1',
      coverage: [CursorUsageWindow(startMs: ms(1), endMs: ms(2) + 86399999)],
      days: [
        CursorUsageDay(
          dayMs: ms(1),
          inputTokens: 14,
          outputTokens: 5,
          cacheReadTokens: 100,
          totalCents: 2,
          eventCount: 1,
          models: {
            'cursor-grok-4.6-high': const CursorUsageModelTotals(
              inputTokens: 14,
              eventCount: 1,
            ),
          },
        ),
      ],
    );

    await store.save(cache);

    expect(await store.load('acct1'), cache);
  });
}
