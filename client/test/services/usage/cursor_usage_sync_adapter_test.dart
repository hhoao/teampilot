import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_coordinator.dart';
import 'package:teampilot/services/usage/cursor_usage_sync_adapter.dart';

void main() {
  final now = DateTime(2026, 10, 28, 9);
  int day(int d) => DateTime(2026, 10, d).millisecondsSinceEpoch;

  CursorUsageSyncAdapter adapter({
    List<CursorUsageAccount>? accounts,
    void Function(String, CursorUsageRange, CursorUsageSyncMode)? onLoad,
    Set<String> failing = const {},
  }) => CursorUsageSyncAdapter(
    now: () => now,
    listAccounts: () async => accounts ?? [_account('a'), _account('b')],
    loadAccount: (accountId, range, mode) async {
      onLoad?.call(accountId, range, mode);
      if (failing.contains(accountId)) throw StateError('boom');
    },
  );

  group('rangeFor', () {
    test('maps presets that map one-to-one', () {
      final sut = adapter();
      expect(
        sut.rangeFor(UsageRange.today),
        const CursorUsagePresetRange(CursorUsagePreset.today),
      );
      expect(
        sut.rangeFor(UsageRange.sevenDays),
        const CursorUsagePresetRange(CursorUsagePreset.sevenDays),
      );
      expect(
        sut.rangeFor(UsageRange.thirtyDays),
        const CursorUsagePresetRange(CursorUsagePreset.thirtyDays),
      );
    });

    test('all maps to the billing cycle so manual mode can expand it', () {
      expect(
        adapter().rangeFor(UsageRange.all),
        const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
      );
    });

    test('last24Hours is a rolling custom window', () {
      final range = adapter().rangeFor(UsageRange.last24Hours);
      expect(range, isA<CursorUsageCustomRange>());
      final custom = range as CursorUsageCustomRange;
      expect(custom.endMs, now.millisecondsSinceEpoch);
      expect(
        custom.startMs,
        now.millisecondsSinceEpoch - const Duration(days: 1).inMilliseconds,
      );
    });

    test('fourteenDays starts at the 14th day back, day-aligned', () {
      final custom = adapter().rangeFor(UsageRange.fourteenDays)
          as CursorUsageCustomRange;
      expect(custom.startMs, day(15));
    });

    test('custom keeps the supplied bounds', () {
      final custom = adapter().rangeFor(
        UsageRange.custom,
        startMs: day(3),
        endMs: day(5),
      ) as CursorUsageCustomRange;
      expect(custom.startMs, day(3));
      expect(custom.endMs, day(5));
    });
  });

  group('syncFor', () {
    test('fetches every enabled account with the mapped range', () async {
      final calls = <(String, CursorUsageRange, CursorUsageSyncMode)>[];
      await adapter(onLoad: (a, r, m) => calls.add((a, r, m))).syncFor(
        UsageRange.sevenDays,
        null,
        null,
      );

      expect(calls.map((c) => c.$1), ['a', 'b']);
      expect(calls.first.$2, const CursorUsagePresetRange(CursorUsagePreset.sevenDays));
      expect(calls.first.$3, CursorUsageSyncMode.auto);
    });

    test('all uses manual mode, full forces full mode', () async {
      final modes = <CursorUsageSyncMode>[];
      final sut = adapter(
        accounts: [_account('a')],
        onLoad: (a, r, m) => modes.add(m),
      );
      await sut.syncFor(UsageRange.all, null, null);
      await sut.syncFor(UsageRange.all, null, null, full: true);
      expect(modes, [CursorUsageSyncMode.manual, CursorUsageSyncMode.full]);
    });

    test('a failing account does not block the rest', () async {
      final seen = <String>[];
      await adapter(
        onLoad: (a, r, m) => seen.add(a),
        failing: {'a'},
      ).syncFor(UsageRange.today, null, null);
      expect(seen, ['a', 'b']);
    });

    test('disabled accounts are skipped', () async {
      final seen = <String>[];
      await adapter(
        accounts: [_account('a', enabled: false), _account('b')],
        onLoad: (a, r, m) => seen.add(a),
      ).syncFor(UsageRange.today, null, null);
      expect(seen, ['b']);
    });
  });
}

CursorUsageAccount _account(String id, {bool enabled = true}) =>
    CursorUsageAccount(
      accountId: id,
      userId: 'user_$id',
      label: id,
      enabled: enabled,
    );
