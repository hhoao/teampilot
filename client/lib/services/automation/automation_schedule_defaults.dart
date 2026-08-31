import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'automation_schedule_calculator.dart';

/// Editor-facing schedule modes: one-shot date+time, relative countdown, or
/// the recurring presets already modeled by [AutomationSchedulePreset].
enum AutomationScheduleMode { once, countdown, recurring }

/// Default once run time — 15 minutes from [now].
DateTime defaultOnceDateTime(DateTime now) =>
    now.add(const Duration(minutes: 15));

/// Rounds [now] up to the next quarter hour as a [TimeOfDay].
///
/// Times already exactly on a quarter boundary roll forward to the next one;
/// otherwise the result is the next 0/15/30/45 boundary (may roll past midnight
/// into 00:00).
TimeOfDay roundUpToNextQuarterHour(DateTime now) {
  final exactOnQuarter =
      now.minute % 15 == 0 && now.second == 0 && now.millisecond == 0;
  final totalMinutes = now.hour * 60 + now.minute;
  final next = exactOnQuarter ? totalMinutes + 15 : _ceilToQuarter(totalMinutes);
  final wrapped = next % (24 * 60);
  return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
}

int _ceilToQuarter(int totalMinutes) {
  final rem = totalMinutes % 15;
  return rem == 0 ? totalMinutes + 15 : totalMinutes + (15 - rem);
}

/// Formats [t] as zero-padded 'HH:mm'.
String formatHourMinute(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Composes a wall-clock [date] + [time] in [timezone] into epoch
/// milliseconds, falling back to UTC when [timezone] is unknown.
int combineLocalDateAndTimeToMs({
  required DateTime date,
  required TimeOfDay time,
  required String timezone,
}) {
  final location = resolveAutomationLocation(timezone);
  return tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  ).millisecondsSinceEpoch;
}

/// Converts a countdown of [durationMinutes] into an absolute epoch-ms target.
int countdownToRunAtMs({required int durationMinutes, required DateTime now}) =>
    now.add(Duration(minutes: durationMinutes)).millisecondsSinceEpoch;
