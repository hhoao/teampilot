import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../utils/logging/logger.dart';
import 'automation_schedule_calculator.dart';
/// Best-effort resolvable timezone identifier for the device: the IANA name
/// when the [timezone] package can map it, otherwise the first curated zone
/// whose current offset matches the device offset, else 'UTC'.
///
/// `DateTime.now().timeZoneName` yields abbreviations ('CST') or Windows
/// names ('China Standard Time') that the tz database cannot resolve, which
/// used to compose once schedules on UTC wall-time. The tz database also has
/// no `Etc/GMT±N` entries, so the fallback reuses the first curated zone that
/// currently matches the device offset — no DST fidelity, but wall-clock
/// composition is correct until the zone next changes offset. When no
/// curated zone matches (a handful of :30/:45 offsets), the result degrades
/// to 'UTC' and the fallback is logged for diagnosability.
String resolveDeviceTimezoneIdentifier() {
  final name = DateTime.now().timeZoneName.trim();
  final offset = DateTime.now().timeZoneOffset;
  if (name.isNotEmpty && _resolvesWithOffset(name, offset)) return name;
  if (offset == Duration.zero) return 'UTC';
  final candidate = _nearestZoneWithOffset(offset);
  if (candidate != null) return candidate;
  appLogger.w(
    '[automations] no curated zone matches device offset $offset; '
    'composing schedules on UTC',
  );
  return 'UTC';
}

bool _resolvesWithOffset(String name, Duration offset) {
  final location = resolveAutomationLocation(name);
  return location.currentTimeZone.offset == offset.inMilliseconds;
}

String? _nearestZoneWithOffset(Duration offset) {
  final target = offset.inMilliseconds;
  // Kept as a plain loop over the pre-sorted key list; determinism matters
  // more than a fancy selection here.
  String? best;
  for (final key in _candidateZoneNames()) {
    final location = resolveAutomationLocation(key);
    if (location.currentTimeZone.offset != target) continue;
    best ??= key;
  }
  return best;
}

const _offsetCandidateZoneNames = [
  // Africa
  'Africa/Abidjan', 'Africa/Algiers', 'Africa/Cairo', 'Africa/Casablanca',
  'Africa/Johannesburg', 'Africa/Lagos', 'Africa/Nairobi',
  // America
  'America/Anchorage', 'America/Argentina/Buenos_Aires', 'America/Bogota',
  'America/Chicago', 'America/Denver', 'America/Detroit', 'America/Edmonton',
  'America/Halifax', 'America/Lima', 'America/Los_Angeles', 'America/Mexico_City',
  'America/New_York', 'America/Phoenix', 'America/Santiago', 'America/Sao_Paulo',
  'America/St_Johns', 'America/Toronto', 'America/Vancouver', 'America/Winnipeg',
  // Asia / Pacific
  'Asia/Bangkok', 'Asia/Dhaka', 'Asia/Dubai', 'Asia/Ho_Chi_Minh', 'Asia/Hong_Kong',
  'Asia/Jakarta', 'Asia/Jerusalem', 'Asia/Kabul', 'Asia/Kathmandu', 'Asia/Kolkata',
  'Asia/Kuala_Lumpur', 'Asia/Manila', 'Asia/Seoul', 'Asia/Shanghai', 'Asia/Singapore',
  'Asia/Taipei', 'Asia/Tehran', 'Asia/Tokyo', 'Asia/Yekaterinburg',
  'Australia/Adelaide', 'Australia/Brisbane', 'Australia/Darwin',
  'Australia/Eucla', 'Australia/Hobart', 'Australia/Melbourne', 'Australia/Perth',
  'Australia/Sydney',
  'Pacific/Auckland', 'Pacific/Chatham', 'Pacific/Fiji', 'Pacific/Guam',
  'Pacific/Honolulu', 'Pacific/Kiritimati', 'Pacific/Marquesas',
  'Pacific/Pago_Pago', 'Pacific/Port_Moresby',
  // Europe / Atlantic
  'Europe/Amsterdam', 'Europe/Athens', 'Europe/Berlin', 'Europe/Brussels',
  'Europe/Bucharest', 'Europe/Budapest', 'Europe/Copenhagen', 'Europe/Dublin',
  'Europe/Helsinki', 'Europe/Istanbul', 'Europe/Kyiv', 'Europe/Lisbon',
  'Europe/London', 'Europe/Madrid', 'Europe/Moscow', 'Europe/Oslo', 'Europe/Paris',
  'Europe/Prague', 'Europe/Rome', 'Europe/Stockholm', 'Europe/Vienna', 'Europe/Warsaw',
  'Europe/Zurich', 'Atlantic/Azores', 'Atlantic/Reykjavik',
  // Fixed / reference zones (Etc/* and UCT are absent from this tzdb build)
  'UTC', 'GMT',
];

Iterable<String> _candidateZoneNames() sync* {
  final database = tz.timeZoneDatabase;
  for (final name in _offsetCandidateZoneNames) {
    if (database.locations.containsKey(name)) yield name;
  }
}

/// Editor-facing schedule modes: one-shot date+time, relative countdown, or
/// the recurring presets already modeled by [AutomationSchedulePreset].
enum AutomationScheduleMode { once, countdown, recurring }

/// Default once run time — 15 minutes from [now].
DateTime defaultOnceDateTime(DateTime now) =>
    now.add(const Duration(minutes: 15));

/// Rounds [now] up to the next quarter hour as a [TimeOfDay].
///
/// An exact 0/15/30/45 boundary rolls to the next one; the result may roll
/// past midnight into 00:00.
TimeOfDay roundUpToNextQuarterHour(DateTime now) {
  final totalMinutes = now.hour * 60 + now.minute;
  final next = _ceilToQuarter(totalMinutes);
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
/// milliseconds, falling back to UTC when [timezone] is unknown. Local times
/// inside a DST gap resolve forward past the gap; ambiguous times resolve to
/// the earlier occurrence.
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
