import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/services/automation/scheduled_task_summary.dart';

Automation _automation({
  required String id,
  required String name,
  bool enabled = true,
  int? nextRunAtMs,
  int? maxRunCount,
  int runCount = 0,
}) {
  return Automation(
    id: id,
    name: name,
    action: AutomationAction.launchPrompt,
    workspaceId: 'ws1',
    isPersonal: true,
    presetId: 'preset-1',
    message: 'ping',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: enabled,
    nextRunAtMs: nextRunAtMs,
    maxRunCount: maxRunCount,
    runCount: runCount,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  test('active tasks exclude disabled and run-limit-reached items', () {
    final summary = ScheduledTaskSummary.fromAutomations([
      _automation(id: 'a2', name: 'B', nextRunAtMs: 200),
      _automation(id: 'a1', name: 'A', nextRunAtMs: 100),
      _automation(id: 'off', name: 'Off', enabled: false, nextRunAtMs: 50),
      _automation(
        id: 'limited',
        name: 'Limited',
        nextRunAtMs: 10,
        maxRunCount: 1,
        runCount: 1,
      ),
    ]);

    expect(summary.active.map((a) => a.id), ['a1', 'a2']);
    expect(summary.nextRunAtMs, 100);
  });

  test('null next-run tasks sort last', () {
    final summary = ScheduledTaskSummary.fromAutomations([
      _automation(id: 'none', name: 'No next'),
      _automation(id: 'soon', name: 'Soon', nextRunAtMs: 300),
    ]);

    expect(summary.active.map((a) => a.id), ['soon', 'none']);
    expect(summary.nextRunAtMs, 300);
  });

  test('same-day next run renders HH:mm', () {
    final now = DateTime(2026, 11, 6, 9);
    final ms = DateTime(2026, 11, 6, 14, 5).millisecondsSinceEpoch;
    expect(formatScheduledTaskNextRun(ms, now: now), '14:05');
  });

  test('other-day next run includes the date', () {
    final now = DateTime(2026, 11, 6, 9);
    final ms = DateTime(2026, 11, 7, 14, 5).millisecondsSinceEpoch;
    expect(formatScheduledTaskNextRun(ms, now: now), '2026-11-07 14:05');
  });
}
