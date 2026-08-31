import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/automation/automation_schedule_defaults.dart';

void main() {
  group('AutomationScheduleMode', () {
    test('exposes once, countdown, recurring', () {
      expect(
        AutomationScheduleMode.values.map((m) => m.name),
        ['once', 'countdown', 'recurring'],
      );
    });
  });

  group('defaultOnceDateTime', () {
    test('is 15 minutes after now', () {
      final now = DateTime(2026, 1, 1, 10, 0);
      expect(defaultOnceDateTime(now), DateTime(2026, 1, 1, 10, 15));
    });
  });

  group('roundUpToNextQuarterHour', () {
    test('rolls exact quarter forward to the next one', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 10, 0, 0, 0)),
        const TimeOfDay(hour: 10, minute: 15),
      );
    });

    test('rounds sub-minute past a quarter up', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 10, 0, 0, 1)),
        const TimeOfDay(hour: 10, minute: 15),
      );
    });

    test('rounds mid-quarter minute up to next quarter', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 10, 16, 20)),
        const TimeOfDay(hour: 10, minute: 30),
      );
    });

    test('rounds 10:44:59.999 up to 10:45', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 10, 44, 59, 999)),
        const TimeOfDay(hour: 10, minute: 45),
      );
    });

    test('rolls exact 10:45 forward to 11:00', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 10, 45, 0, 0)),
        const TimeOfDay(hour: 11, minute: 0),
      );
    });

    test('rounds 10:47 up to 11:00', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 10, 47)),
        const TimeOfDay(hour: 11, minute: 0),
      );
    });

    test('wraps 23:52 to 00:00 next day', () {
      expect(
        roundUpToNextQuarterHour(DateTime(2026, 1, 1, 23, 52)),
        const TimeOfDay(hour: 0, minute: 0),
      );
    });
  });

  group('formatHourMinute', () {
    test('zero-pads hour and minute', () {
      expect(formatHourMinute(const TimeOfDay(hour: 9, minute: 5)), '09:05');
      expect(formatHourMinute(const TimeOfDay(hour: 23, minute: 59)), '23:59');
      expect(formatHourMinute(const TimeOfDay(hour: 0, minute: 0)), '00:00');
    });
  });

  group('combineLocalDateAndTimeToMs', () {
    test('composes wall clock in UTC', () {
      final ms = combineLocalDateAndTimeToMs(
        date: DateTime(2026, 1, 1),
        time: const TimeOfDay(hour: 15, minute: 30),
        timezone: 'UTC',
      );
      expect(ms, DateTime.utc(2026, 1, 1, 15, 30).millisecondsSinceEpoch);
    });

    test('composes wall clock in America/New_York', () {
      final ms = combineLocalDateAndTimeToMs(
        date: DateTime(2026, 1, 1),
        time: const TimeOfDay(hour: 9, minute: 0),
        timezone: 'America/New_York',
      );
      // EST = UTC-5 in January.
      expect(ms, DateTime.utc(2026, 1, 1, 14, 0).millisecondsSinceEpoch);
    });

    test('falls back to UTC for unknown timezone', () {
      final ms = combineLocalDateAndTimeToMs(
        date: DateTime(2026, 1, 1),
        time: const TimeOfDay(hour: 15, minute: 30),
        timezone: 'Not/AZone',
      );
      expect(ms, DateTime.utc(2026, 1, 1, 15, 30).millisecondsSinceEpoch);
    });

    test('resolves local times inside a DST gap forward past the gap', () {
      // 2026-03-08 02:30 does not exist in America/New_York (spring forward).
      final ms = combineLocalDateAndTimeToMs(
        date: DateTime(2026, 3, 8),
        time: const TimeOfDay(hour: 2, minute: 30),
        timezone: 'America/New_York',
      );
      expect(ms, DateTime.utc(2026, 3, 8, 7, 30).millisecondsSinceEpoch);
    });
  });

  group('countdownToRunAtMs', () {
    test('adds the countdown duration to now', () {
      final ms = countdownToRunAtMs(
        durationMinutes: 15,
        now: DateTime(2026, 1, 1, 10, 0),
      );
      expect(ms, DateTime(2026, 1, 1, 10, 15).millisecondsSinceEpoch);
    });
  });
}
