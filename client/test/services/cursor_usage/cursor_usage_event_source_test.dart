import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_event_source.dart';

int ms(int day) => DateTime(2026, 10, day).millisecondsSinceEpoch;

const _account = CursorUsageAccount(
  accountId: 'acct1',
  userId: 'user_a',
  label: 'A',
  source: CursorAccountSource.discovered,
);

CursorUsageCache cacheWithDays() => CursorUsageCache(
  accountId: 'acct1',
  days: [
    CursorUsageDay(
      dayMs: ms(1),
      inputTokens: 10,
      outputTokens: 5,
      cacheReadTokens: 100,
      cacheWriteTokens: 2,
      totalCents: 3.5,
      eventCount: 2,
      models: const {
        'cursor-grok-4.6-high': CursorUsageModelTotals(
          inputTokens: 10,
          outputTokens: 5,
          cacheReadTokens: 100,
          cacheWriteTokens: 2,
          totalCents: 3.5,
          eventCount: 2,
        ),
        '': CursorUsageModelTotals(totalCents: 1, eventCount: 1),
      },
    ),
  ],
);

void main() {
  test('synthesizes one event per account, day, and model', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [_account],
      loadCache: (_) async => cacheWithDays(),
    );

    final events = await source.loadEvents();

    expect(events.length, 2);
    final grok = events.firstWhere((e) => e.model == 'cursor-grok-4.6-high');
    expect(
      grok.requestId,
      'cursor-account:acct1:${ms(1)}:cursor-grok-4.6-high',
    );
    expect(grok.sessionId, cursorAccountUsageSessionId);
    expect(grok.inputTokens, 10);
    expect(grok.cacheCreationTokens, 2);
    expect(grok.timestampMs, ms(1));
    expect(grok.costMicroUsd, 35000);
    expect(events.every((e) => e.cli.name == 'cursor'), isTrue);
  });

  test('an empty model name becomes cursor-auto', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [_account],
      loadCache: (_) async => cacheWithDays(),
    );
    final events = await source.loadEvents();
    expect(events.map((e) => e.model), contains('cursor-auto'));
  });

  test('disabled accounts are skipped', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [
        const CursorUsageAccount(
          accountId: 'acct1',
          userId: 'user_a',
          label: 'A',
          source: CursorAccountSource.manual,
          enabled: false,
        ),
      ],
      loadCache: (_) async => cacheWithDays(),
    );
    expect(await source.loadEvents(), isEmpty);
  });

  test('two accounts with identical days do not collide', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [
        _account,
        const CursorUsageAccount(
          accountId: 'acct2',
          userId: 'user_b',
          label: 'B',
          source: CursorAccountSource.manual,
        ),
      ],
      loadCache: (accountId) async =>
          CursorUsageCache(accountId: accountId, days: cacheWithDays().days),
    );
    final events = await source.loadEvents();
    expect(events.map((e) => e.requestId).toSet().length, events.length);
  });
}
