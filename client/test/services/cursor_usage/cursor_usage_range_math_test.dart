import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_range_math.dart';

int ms(int year, int month, int day, [int hour = 0]) =>
    DateTime(year, month, day, hour).millisecondsSinceEpoch;

void main() {
  group('cursorUsageResolveRange', () {
    test('billing cycle wins when supplied', () {
      final cycle = CursorUsageWindow(
        startMs: ms(2026, 10, 6),
        endMs: cursorUsageDayEndMs(ms(2026, 11, 6)),
      );
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
        nowMs: ms(2026, 10, 28, 12),
        billingCycle: cycle,
      );
      expect(resolved, cycle);
    });

    test('billing cycle falls back to the calendar month', () {
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
        nowMs: ms(2026, 10, 28, 12),
      );
      expect(resolved.startMs, ms(2026, 10, 1));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 10, 28)));
    });

    test('sevenDays covers today plus six previous days', () {
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.sevenDays),
        nowMs: ms(2026, 10, 28, 12),
      );
      expect(resolved.startMs, ms(2026, 10, 22));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 10, 28)));
    });

    test('lastMonth covers the whole previous calendar month', () {
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.lastMonth),
        nowMs: ms(2026, 3, 15, 9),
      );
      expect(resolved.startMs, ms(2026, 2, 1));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 2, 28)));
    });

    test('custom range snaps to whole local days', () {
      final resolved = cursorUsageResolveRange(
        range: CursorUsageCustomRange(
          startMs: ms(2026, 9, 29, 13),
          endMs: ms(2026, 10, 28, 4),
        ),
        nowMs: ms(2026, 10, 28, 12),
      );
      expect(resolved.startMs, ms(2026, 9, 29));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 10, 28)));
    });
  });

  group('cursorUsageMissingWindows', () {
    test('returns the whole request when nothing is covered', () {
      final requested = CursorUsageWindow(
        startMs: ms(2026, 10, 1),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 3)),
      );
      expect(
        cursorUsageMissingWindows(covered: const [], requested: requested),
        [requested],
      );
    });

    test('returns nothing when the request is fully covered', () {
      final day = CursorUsageWindow(
        startMs: ms(2026, 10, 1),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 2)),
      );
      expect(
        cursorUsageMissingWindows(covered: [day], requested: day),
        isEmpty,
      );
    });

    test('splits a request around a covered middle', () {
      final requested = CursorUsageWindow(
        startMs: ms(2026, 10, 1),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 5)),
      );
      final covered = CursorUsageWindow(
        startMs: ms(2026, 10, 3),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 3)),
      );
      final gaps = cursorUsageMissingWindows(
        covered: [covered],
        requested: requested,
      );
      expect(gaps.length, 2);
      expect(gaps[0].startMs, ms(2026, 10, 1));
      expect(gaps[0].endMs, cursorUsageDayEndMs(ms(2026, 10, 2)));
      expect(gaps[1].startMs, ms(2026, 10, 4));
      expect(gaps[1].endMs, cursorUsageDayEndMs(ms(2026, 10, 5)));
    });

    test('treats adjacent windows as contiguous', () {
      final merged = cursorUsageMergeWindows([
        CursorUsageWindow(
          startMs: ms(2026, 10, 1),
          endMs: cursorUsageDayEndMs(ms(2026, 10, 2)),
        ),
        CursorUsageWindow(
          startMs: ms(2026, 10, 3),
          endMs: cursorUsageDayEndMs(ms(2026, 10, 4)),
        ),
      ]);
      expect(merged.length, 1);
      expect(merged.single.startMs, ms(2026, 10, 1));
      expect(merged.single.endMs, cursorUsageDayEndMs(ms(2026, 10, 4)));
    });
  });
}
