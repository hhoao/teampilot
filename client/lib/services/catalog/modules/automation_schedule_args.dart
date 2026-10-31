import '../../../models/automation.dart';
import '../../automation/automation_schedule_calculator.dart';
import '../catalog_kind.dart';

/// Parsed schedule arguments for an automation create/update request.
class AutomationScheduleSpec {
  const AutomationScheduleSpec({
    required this.preset,
    required this.timezone,
    required this.dtstartMs,
    this.customCron,
    this.dayOfWeek,
    this.minute = 0,
    this.hourMinute = '09:00',
    this.runAtMs,
  });

  final AutomationSchedulePreset preset;
  final String? customCron;
  final int? dayOfWeek;
  final int minute;
  final String hourMinute;
  final String timezone;
  final int dtstartMs;
  final int? runAtMs;
}

/// Parses the model-supplied `schedule` object into an
/// [AutomationScheduleSpec].
///
/// Every malformed value — wrong type, out-of-range number, unparsable
/// `HH:mm`, invalid cron, past `at` — surfaces as
/// [CatalogException]`('schedule_invalid', ...)`; defaults are only applied
/// when the key is absent, never to mask a type error.
AutomationScheduleSpec parseAutomationSchedule(
  Object? raw, {
  required AutomationScheduleCalculator calculator,
  required String defaultTimezone,
  required int now,
}) {
  if (raw is! Map) {
    throw CatalogException('schedule_invalid', 'schedule is required');
  }
  final map = _stringKeyedMap(raw);
  const defaultTime = '09:00';
  try {
    final type = _optionalText(map, 'type')?.toLowerCase();
    if (type == null) {
      throw ArgumentError('schedule.type is required');
    }
    final timezone = _optionalText(map, 'timezone') ?? defaultTimezone;
    final dtstartMs = _optionalInt(map, 'dtstart_ms') ?? now;
    switch (type) {
      case 'hourly':
        final minute = _optionalInt(map, 'minute') ?? 0;
        if (minute < 0 || minute > 59) {
          throw ArgumentError('minute must be 0..59');
        }
        return AutomationScheduleSpec(
          preset: AutomationSchedulePreset.hourly,
          minute: minute,
          hourMinute: defaultTime,
          timezone: timezone,
          dtstartMs: dtstartMs,
        );
      case 'daily':
      case 'weekdays':
        final time = _optionalText(map, 'time') ?? defaultTime;
        parseHourMinute(time);
        return AutomationScheduleSpec(
          preset: type == 'daily'
              ? AutomationSchedulePreset.daily
              : AutomationSchedulePreset.weekdays,
          hourMinute: time,
          timezone: timezone,
          dtstartMs: dtstartMs,
        );
      case 'weekly':
        final time = _optionalText(map, 'time') ?? defaultTime;
        parseHourMinute(time);
        final day = _optionalInt(map, 'day_of_week') ?? 1;
        if (day < 1 || day > 7) {
          throw ArgumentError('day_of_week must be 1..7');
        }
        return AutomationScheduleSpec(
          preset: AutomationSchedulePreset.weekly,
          hourMinute: time,
          dayOfWeek: day,
          timezone: timezone,
          dtstartMs: dtstartMs,
        );
      case 'custom':
        final cron = _optionalText(map, 'cron');
        if (cron == null || !calculator.isValidCron(cron)) {
          throw ArgumentError('invalid cron expression');
        }
        return AutomationScheduleSpec(
          preset: AutomationSchedulePreset.custom,
          customCron: cron,
          timezone: timezone,
          dtstartMs: dtstartMs,
        );
      case 'once':
        final at = _timestamp(map['at'], 'at');
        if (at == null || at <= now) {
          throw ArgumentError('at must be a future timestamp');
        }
        return AutomationScheduleSpec(
          preset: AutomationSchedulePreset.once,
          runAtMs: at,
          timezone: timezone,
          dtstartMs: dtstartMs,
        );
      default:
        throw ArgumentError('unknown schedule type: $type');
    }
  } on ArgumentError catch (error) {
    throw CatalogException(
      'schedule_invalid',
      error.message?.toString() ?? 'invalid schedule',
    );
  } on FormatException catch (error) {
    throw CatalogException('schedule_invalid', error.message);
  }
}

Map<String, Object?> _stringKeyedMap(Map raw) {
  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      throw CatalogException(
        'schedule_invalid',
        'schedule keys must be strings',
      );
    }
    map[key] = entry.value;
  }
  return map;
}

String? _optionalText(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw ArgumentError('schedule.$key must be a string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! num) {
    throw ArgumentError('schedule.$key must be a number');
  }
  return value.toInt();
}

int? _timestamp(Object? raw, String key) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String && raw.trim().isNotEmpty) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) {
      throw ArgumentError('schedule.$key must be an ISO timestamp');
    }
    return parsed.millisecondsSinceEpoch;
  }
  throw ArgumentError(
    'schedule.$key must be an integer epoch or ISO timestamp',
  );
}
