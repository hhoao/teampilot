import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../models/automation.dart';

bool _timezoneInitialized = false;

void ensureAutomationTimezoneInitialized() {
  if (_timezoneInitialized) return;
  tz_data.initializeTimeZones();
  _timezoneInitialized = true;
}

/// Resolves [timezone] to a `tz.Location`, falling back to UTC for unknown
/// names. Initializes the timezone database on first use.
tz.Location resolveAutomationLocation(String timezone) {
  ensureAutomationTimezoneInitialized();
  try {
    return tz.getLocation(timezone);
  } on Object {
    return tz.UTC;
  }
}

(int hour, int minute) parseHourMinute(String raw) {
  final parts = raw.split(':');
  if (parts.length != 2) {
    throw ArgumentError('hourMinute must be HH:mm');
  }
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw ArgumentError('hourMinute out of range');
  }
  return (hour, minute);
}

class AutomationScheduleCalculator {
  String scheduleExpression(Automation automation) {
    final (hour, minute) = parseHourMinute(automation.hourMinute);
    switch (automation.preset) {
      case AutomationSchedulePreset.hourly:
        return '${automation.minute} * * * *';
      case AutomationSchedulePreset.daily:
        return '$minute $hour * * *';
      case AutomationSchedulePreset.weekdays:
        return '$minute $hour * * 1-5';
      case AutomationSchedulePreset.weekly:
        final day = _weeklyCronDay(automation.dayOfWeek ?? 1);
        return '$minute $hour * * $day';
      case AutomationSchedulePreset.custom:
        return automation.customCron?.trim() ?? '';
      case AutomationSchedulePreset.once:
        return '';
    }
  }

  int _weeklyCronDay(int dayOfWeek) {
    // Model: 1=Mon..7=Sun. Cron: 0=Sun..6=Sat.
    if (dayOfWeek == 7) return 0;
    return dayOfWeek.clamp(1, 7);
  }

  bool isValidCron(String expression) {
    try {
      _parseCron(expression);
      return true;
    } on Object {
      return false;
    }
  }

  String formatScheduleSummary(Automation automation) {
    final (hour, minute) = parseHourMinute(automation.hourMinute);
    final time =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    switch (automation.preset) {
      case AutomationSchedulePreset.hourly:
        return 'Hourly at :${automation.minute.toString().padLeft(2, '0')}';
      case AutomationSchedulePreset.daily:
        return 'Daily at $time';
      case AutomationSchedulePreset.weekdays:
        return 'Weekdays at $time';
      case AutomationSchedulePreset.weekly:
        return 'Weekly (${automation.dayOfWeek ?? 1}) at $time';
      case AutomationSchedulePreset.custom:
        return automation.customCron?.trim().isNotEmpty == true
            ? automation.customCron!.trim()
            : 'Custom';
      case AutomationSchedulePreset.once:
        return 'Once';
    }
  }

  int? computeNextRunAtMs(Automation automation, {required int afterMs}) {
    automation.validate();

    if (automation.preset == AutomationSchedulePreset.once) {
      final runAt = automation.runAtMs;
      return runAt != null && runAt > afterMs ? runAt : null;
    }

    final location = resolveAutomationLocation(automation.timezone);
    final after = tz.TZDateTime.fromMillisecondsSinceEpoch(location, afterMs);
    final dtstart = tz.TZDateTime.fromMillisecondsSinceEpoch(
      location,
      automation.dtstartMs,
    );
    final anchor = after.isBefore(dtstart) ? dtstart : after;

    if (automation.preset == AutomationSchedulePreset.custom) {
      final cron = _parseCron(automation.customCron ?? '');
      return _nextCronOccurrence(cron, anchor, dtstart).millisecondsSinceEpoch;
    }

    final (hour, minute) = parseHourMinute(automation.hourMinute);
    switch (automation.preset) {
      case AutomationSchedulePreset.hourly:
        return _nextHourly(
          anchor,
          dtstart,
          automation.minute,
        ).millisecondsSinceEpoch;
      case AutomationSchedulePreset.daily:
        return _nextDaily(anchor, dtstart, hour, minute).millisecondsSinceEpoch;
      case AutomationSchedulePreset.weekdays:
        return _nextWeekdays(
          anchor,
          dtstart,
          hour,
          minute,
        ).millisecondsSinceEpoch;
      case AutomationSchedulePreset.weekly:
        return _nextWeekly(
          anchor,
          dtstart,
          hour,
          minute,
          automation.dayOfWeek ?? 1,
        ).millisecondsSinceEpoch;
      case AutomationSchedulePreset.custom:
        throw StateError('unreachable');
      case AutomationSchedulePreset.once:
        throw StateError('unreachable');
    }
  }

  tz.TZDateTime _nextHourly(
    tz.TZDateTime after,
    tz.TZDateTime dtstart,
    int minute,
  ) {
    var candidate = tz.TZDateTime(
      after.location,
      after.year,
      after.month,
      after.day,
      after.hour,
      minute,
    );
    if (!candidate.isAfter(after) || candidate.isBefore(dtstart)) {
      candidate = candidate.add(const Duration(hours: 1));
    }
    while (candidate.isBefore(dtstart)) {
      candidate = candidate.add(const Duration(hours: 1));
    }
    return candidate;
  }

  tz.TZDateTime _nextDaily(
    tz.TZDateTime after,
    tz.TZDateTime dtstart,
    int hour,
    int minute,
  ) {
    var candidate = tz.TZDateTime(
      after.location,
      after.year,
      after.month,
      after.day,
      hour,
      minute,
    );
    if (!candidate.isAfter(after) || candidate.isBefore(dtstart)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    while (candidate.isBefore(dtstart)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  bool _isWeekday(tz.TZDateTime date) {
    // TZDateTime.weekday: 1=Mon..7=Sun
    return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
  }

  tz.TZDateTime _nextWeekdays(
    tz.TZDateTime after,
    tz.TZDateTime dtstart,
    int hour,
    int minute,
  ) {
    var candidate = _nextDaily(after, dtstart, hour, minute);
    while (!_isWeekday(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  tz.TZDateTime _nextWeekly(
    tz.TZDateTime after,
    tz.TZDateTime dtstart,
    int hour,
    int minute,
    int dayOfWeek,
  ) {
    final targetWeekday = dayOfWeek == 7 ? DateTime.sunday : dayOfWeek;
    var candidate = tz.TZDateTime(
      after.location,
      after.year,
      after.month,
      after.day,
      hour,
      minute,
    );
    while (candidate.weekday != targetWeekday ||
        !candidate.isAfter(after) ||
        candidate.isBefore(dtstart)) {
      candidate = candidate.add(const Duration(days: 1));
      candidate = tz.TZDateTime(
        candidate.location,
        candidate.year,
        candidate.month,
        candidate.day,
        hour,
        minute,
      );
    }
    return candidate;
  }

  _ParsedCron _parseCron(String expression) {
    final parts = expression.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      throw ArgumentError('cron must have 5 fields');
    }
    return _ParsedCron(
      minutes: _parseField(parts[0], 0, 59),
      hours: _parseField(parts[1], 0, 23),
      daysOfMonth: _parseField(parts[2], 1, 31),
      months: _parseField(parts[3], 1, 12),
      daysOfWeek: _parseField(
        parts[4],
        0,
        7,
      ).map((d) => d == 7 ? 0 : d).toSet(),
    );
  }

  Set<int> _parseField(String raw, int min, int max) {
    final trimmed = raw.trim();
    if (trimmed == '*') {
      return {for (var i = min; i <= max; i++) i};
    }
    final values = <int>{};
    for (final part in trimmed.split(',')) {
      final stepParts = part.split('/');
      final range = stepParts.first.trim();
      final step = stepParts.length == 2 ? int.parse(stepParts[1]) : 1;
      int start;
      int end;
      if (range == '*') {
        start = min;
        end = max;
      } else if (range.contains('-')) {
        final bounds = range.split('-');
        start = int.parse(bounds[0]);
        end = int.parse(bounds[1]);
      } else {
        start = int.parse(range);
        end = start;
      }
      for (var value = start; value <= end; value += step) {
        if (value < min || value > max) {
          throw ArgumentError('cron field out of range');
        }
        values.add(value);
      }
    }
    if (values.isEmpty) throw ArgumentError('empty cron field');
    return values;
  }

  tz.TZDateTime _nextCronOccurrence(
    _ParsedCron cron,
    tz.TZDateTime after,
    tz.TZDateTime dtstart,
  ) {
    var candidate = tz.TZDateTime(
      after.location,
      after.year,
      after.month,
      after.day,
      after.hour,
      after.minute,
    ).add(const Duration(minutes: 1));
    if (candidate.isBefore(dtstart)) {
      candidate = dtstart;
    }
    for (var i = 0; i < 60 * 24 * 366; i++) {
      if (_cronMatches(cron, candidate)) return candidate;
      candidate = candidate.add(const Duration(minutes: 1));
    }
    throw StateError('Unable to compute next cron run');
  }

  bool _cronMatches(_ParsedCron cron, tz.TZDateTime date) {
    if (!cron.minutes.contains(date.minute)) return false;
    if (!cron.hours.contains(date.hour)) return false;
    if (!cron.months.contains(date.month)) return false;
    final domRestricted = cron.daysOfMonth.length != 31;
    final dowRestricted = cron.daysOfWeek.length != 7;
    final domMatch = cron.daysOfMonth.contains(date.day);
    final dowMatch = cron.daysOfWeek.contains(
      date.weekday == DateTime.sunday ? 0 : date.weekday,
    );
    if (domRestricted && dowRestricted) {
      return domMatch || dowMatch;
    }
    return domMatch && dowMatch;
  }
}

class _ParsedCron {
  const _ParsedCron({
    required this.minutes,
    required this.hours,
    required this.daysOfMonth,
    required this.months,
    required this.daysOfWeek,
  });

  final Set<int> minutes;
  final Set<int> hours;
  final Set<int> daysOfMonth;
  final Set<int> months;
  final Set<int> daysOfWeek;
}
