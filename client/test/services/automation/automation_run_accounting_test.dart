import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/services/automation/automation_run_accounting.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';

Automation _daily({int maxRunCount = 0, bool enabled = true}) {
  return Automation(
    id: 'a1',
    name: 'daily',
    action: AutomationAction.runCommand,
    workspaceId: 'ws1',
    command: 'echo hi',
    message: '',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '02:00',
    timezone: 'Asia/Shanghai',
    dtstartMs: 0,
    maxRunCount: maxRunCount == 0 ? null : maxRunCount,
    enabled: enabled,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

void main() {
  final accounting = AutomationRunAccounting(AutomationScheduleCalculator());

  test('increments runCount and recomputes next run', () {
    final now = DateTime(2026, 11, 2, 3).millisecondsSinceEpoch;
    final next = accounting.advance(
      automation: _daily(),
      lastRunAtMs: now,
      nowMs: now,
    );
    expect(next.runCount, 1);
    expect(next.lastRunAtMs, now);
    expect(next.enabled, isTrue);
    expect(next.nextRunAtMs, isNotNull);
    expect(next.nextRunAtMs! > now, isTrue);
  });

  test('disables when the run limit is reached', () {
    final now = DateTime(2026, 11, 2, 3).millisecondsSinceEpoch;
    final next = accounting.advance(
      automation: _daily(maxRunCount: 1),
      lastRunAtMs: now,
      nowMs: now,
    );
    expect(next.runCount, 1);
    expect(next.enabled, isFalse);
    expect(next.nextRunAtMs, isNull);
  });

  test('leaves a disabled automation disabled', () {
    final now = DateTime(2026, 11, 2, 3).millisecondsSinceEpoch;
    final next = accounting.advance(
      automation: _daily(enabled: false),
      lastRunAtMs: now,
      nowMs: now,
    );
    expect(next.enabled, isFalse);
    expect(next.nextRunAtMs, isNull);
    expect(next.runCount, 1);
  });
}
