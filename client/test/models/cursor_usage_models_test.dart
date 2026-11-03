import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_report.dart';

void main() {
  test('cookie rebuilds the WorkosCursorSessionToken header', () {
    const credentials = CursorAccountCredentials(
      accountId: 'abc123',
      userId: 'user_01ABC',
      token: 'eyJ.payload.sig',
      expiresAtMs: 2000000000000,
    );
    expect(
      credentials.cookie,
      'WorkosCursorSessionToken=user_01ABC%3A%3AeyJ.payload.sig',
    );
  });

  test('isExpired treats a token inside the 60s guard as expired', () {
    const account = CursorUsageAccount(
      accountId: 'abc123',
      userId: 'user_01ABC',
      label: 'Cursor · abc123',
      expiresAtMs: 1000000,
    );
    expect(account.isExpired(939999), isFalse);
    expect(account.isExpired(940000), isTrue);
    expect(account.isExpired(2000000), isTrue);
  });

  test('day totals round-trip through json', () {
    const day = CursorUsageDay(
      dayMs: 1790000000000,
      inputTokens: 10,
      outputTokens: 20,
      cacheReadTokens: 30,
      cacheWriteTokens: 40,
      totalCents: 1.5,
      chargedCents: 0.5,
      eventCount: 2,
      models: {
        'cursor-grok-4.6-high': CursorUsageModelTotals(
          inputTokens: 10,
          outputTokens: 20,
          cacheReadTokens: 30,
          cacheWriteTokens: 40,
          totalCents: 1.5,
          chargedCents: 0.5,
          eventCount: 2,
        ),
      },
    );
    expect(CursorUsageDay.fromJson(day.toJson()), day);
  });
}
