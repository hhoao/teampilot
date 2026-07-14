import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';

void main() {
  test('Automation round-trips JSON', () {
    final a = Automation(
      id: 'a1',
      name: 'Reset',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.hourly,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_000_000,
      enabled: true,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final json = a.toJson();
    final back = Automation.fromJson(json);
    expect(back.id, 'a1');
    expect(back.action, AutomationAction.scheduledMessage);
    expect(back, a);
  });

  test('Automation round-trips JSON with run limit fields', () {
    final a = Automation(
      id: 'a1',
      name: 'Once',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.daily,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_000_000,
      enabled: false,
      maxRunCount: 1,
      runCount: 1,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final back = Automation.fromJson(a.toJson());
    expect(back.maxRunCount, 1);
    expect(back.runCount, 1);
    expect(back.isRunLimitReached, isTrue);
    expect(back, a);
  });

  test('launchPrompt round-trips presetId', () {
    final a = Automation(
      id: 'x',
      name: 'n',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws',
      isPersonal: true,
      presetId: 'preset-1',
      targetMemberId: 'team-lead',
      message: 'ping',
      preset: AutomationSchedulePreset.daily,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 0,
      enabled: true,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    a.validate();
    final back = Automation.fromJson(a.toJson());
    expect(back.presetId, 'preset-1');
    expect(back.isPersonal, isTrue);
  });

  test('launchPrompt round-trips project and worktree paths', () {
    final a = Automation(
      id: 'x',
      name: 'n',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws',
      isPersonal: true,
      presetId: 'preset-1',
      projectFolderPath: '/repo',
      workingDirectoryPath: '/repo/feature',
      message: 'ping',
      preset: AutomationSchedulePreset.daily,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 0,
      enabled: true,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    a.validate();
    final back = Automation.fromJson(a.toJson());
    expect(back.projectFolderPath, '/repo');
    expect(back.workingDirectoryPath, '/repo/feature');
    expect(back.launchContext.projectFolderPath, '/repo');
    expect(back.launchContext.workingDirectoryPath, '/repo/feature');
  });

  test('scheduledMessage requires sessionId', () {
    expect(
      () => Automation(
        id: 'x',
        name: 'n',
        action: AutomationAction.scheduledMessage,
        workspaceId: 'ws',
        message: 'ping',
        preset: AutomationSchedulePreset.daily,
        minute: 0,
        hourMinute: '09:00',
        timezone: 'UTC',
        dtstartMs: 0,
        enabled: true,
        createdAtMs: 0,
        updatedAtMs: 0,
      ).validate(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('maxRunCount must be positive when set', () {
    expect(
      () => Automation(
        id: 'x',
        name: 'n',
        action: AutomationAction.launchPrompt,
        workspaceId: 'ws',
        isPersonal: true,
        presetId: 'preset-1',
        targetMemberId: 'team-lead',
        message: 'ping',
        preset: AutomationSchedulePreset.daily,
        minute: 0,
        hourMinute: '09:00',
        timezone: 'UTC',
        dtstartMs: 0,
        enabled: true,
        maxRunCount: 0,
        createdAtMs: 0,
        updatedAtMs: 0,
      ).validate(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('AutomationRun round-trips JSON', () {
    const run = AutomationRun(
      id: 'r1',
      automationId: 'a1',
      workspaceId: 'ws1',
      scheduledForMs: 100,
      status: AutomationRunStatus.completed,
      trigger: AutomationRunTrigger.manual,
      sessionId: 's1',
      completedAtMs: 200,
    );
    expect(AutomationRun.fromJson(run.toJson()), run);
  });
}
