import 'package:teampilot/models/automation_tab_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

Automation _automation({
  AutomationSchedulePreset preset = AutomationSchedulePreset.daily,
  int minute = 0,
  String hourMinute = '09:00',
  String? customCron,
  int? dayOfWeek,
}) {
  return Automation(
    id: 'a1',
    name: 'Test',
    action: AutomationAction.launchPrompt,
    workspaceId: 'ws1',
    launchProfileId: AutomationTabScope.simpleLaunchProfileId,
    cli: CliTool.claude,
    message: 'hi',
    preset: preset,
    minute: minute,
    hourMinute: hourMinute,
    customCron: customCron,
    dayOfWeek: dayOfWeek,
    timezone: 'UTC',
    dtstartMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    enabled: true,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  final calc = AutomationScheduleCalculator();

  test('hourly next run', () {
    final automation = _automation(
      preset: AutomationSchedulePreset.hourly,
      minute: 30,
    );
    final after = DateTime.utc(2026, 1, 1, 10, 15).millisecondsSinceEpoch;
    final next = calc.computeNextRunAtMs(automation, afterMs: after);
    expect(DateTime.fromMillisecondsSinceEpoch(next, isUtc: true).minute, 30);
  });

  test('daily next run', () {
    final automation = _automation(hourMinute: '09:00');
    final after = DateTime.utc(2026, 1, 1, 10, 0).millisecondsSinceEpoch;
    final next = calc.computeNextRunAtMs(automation, afterMs: after);
    final dt = DateTime.fromMillisecondsSinceEpoch(next, isUtc: true);
    expect(dt.hour, 9);
    expect(dt.day, 2);
  });

  test('weekdays skips weekend', () {
    final automation = _automation(
      preset: AutomationSchedulePreset.weekdays,
      hourMinute: '09:00',
    );
    // 2026-01-02 is Friday
    final after = DateTime.utc(2026, 1, 2, 10, 0).millisecondsSinceEpoch;
    final next = calc.computeNextRunAtMs(automation, afterMs: after);
    final dt = DateTime.fromMillisecondsSinceEpoch(next, isUtc: true);
    expect(dt.weekday, DateTime.monday);
  });

  test('weekly Monday', () {
    final automation = _automation(
      preset: AutomationSchedulePreset.weekly,
      hourMinute: '10:00',
      dayOfWeek: 1,
    );
    final after = DateTime.utc(2026, 1, 1, 11, 0).millisecondsSinceEpoch;
    final next = calc.computeNextRunAtMs(automation, afterMs: after);
    final dt = DateTime.fromMillisecondsSinceEpoch(next, isUtc: true);
    expect(dt.weekday, DateTime.monday);
    expect(dt.hour, 10);
  });

  test('custom cron every 2 hours', () {
    final automation = _automation(
      preset: AutomationSchedulePreset.custom,
      customCron: '0 */2 * * *',
    );
    final after = DateTime.utc(2026, 1, 1, 1, 0).millisecondsSinceEpoch;
    final next = calc.computeNextRunAtMs(automation, afterMs: after);
    expect(DateTime.fromMillisecondsSinceEpoch(next, isUtc: true).hour, 2);
  });

  test('isValidCron rejects bad expression', () {
    expect(calc.isValidCron('bad cron'), isFalse);
    expect(calc.isValidCron('0 */2 * * *'), isTrue);
  });
}
