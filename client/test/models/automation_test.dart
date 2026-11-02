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

  test('automation JSON does not persist launch security policy', () {
    final automation = Automation(
      id: 'security',
      name: 'Secure launch',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws',
      isPersonal: true,
      presetId: 'preset-1',
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

    final json = automation.toJson();
    expect(json.containsKey('launchSecurityPolicy'), isFalse);
    expect(json.containsKey('dangerouslySkipPermissions'), isFalse);
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

  test('once round-trips runAtMs', () {
    final a = Automation(
      id: 'a1',
      name: 'Once',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.once,
      runAtMs: 1_700_000_100_000,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_100_000,
      enabled: true,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    a.validate();
    final back = Automation.fromJson(a.toJson());
    expect(back.preset, AutomationSchedulePreset.once);
    expect(back.runAtMs, 1_700_000_100_000);
    expect(back.hasRunLimit, isTrue);
    expect(back.effectiveMaxRunCount, 1);
    expect(back.isRunLimitReached, isFalse);
    expect(back, a);
  });

  test('once requires runAtMs', () {
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
        preset: AutomationSchedulePreset.once,
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

  test('once rejects non-positive runAtMs', () {
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
        preset: AutomationSchedulePreset.once,
        runAtMs: 0,
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

  test('non-once presets keep the stored maxRunCount', () {
    final limited = Automation(
      id: 'a1',
      name: 'Limited',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 0,
      enabled: true,
      maxRunCount: 3,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    expect(limited.hasRunLimit, isTrue);
    expect(limited.effectiveMaxRunCount, 3);
    expect(limited.isRunLimitReached, isFalse);

    final unlimited = Automation(
      id: 'a2',
      name: 'Unlimited',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 0,
      enabled: true,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    expect(unlimited.hasRunLimit, isFalse);
    expect(unlimited.effectiveMaxRunCount, isNull);
  });

  test('once reaches run limit without maxRunCount', () {
    final a = Automation(
      id: 'a1',
      name: 'Once',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.once,
      runAtMs: 1_700_000_100_000,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_100_000,
      enabled: true,
      runCount: 1,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    expect(a.maxRunCount, isNull);
    expect(a.hasRunLimit, isTrue);
    expect(a.effectiveMaxRunCount, 1);
    expect(a.isRunLimitReached, isTrue);
  });

  test('once overrides a stored maxRunCount greater than 1', () {
    final a = Automation(
      id: 'a1',
      name: 'Once',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.once,
      runAtMs: 1_700_000_100_000,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_100_000,
      enabled: true,
      maxRunCount: 5,
      runCount: 1,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    expect(a.hasRunLimit, isTrue);
    expect(a.effectiveMaxRunCount, 1);
    expect(a.isRunLimitReached, isTrue);
  });

  test('legacy automation without runAtMs parses null', () {
    final a = Automation(
      id: 'a1',
      name: 'Daily',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 0,
      enabled: true,
      maxRunCount: 3,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final back = Automation.fromJson(a.toJson());
    expect(back.runAtMs, isNull);
    expect(back.preset, AutomationSchedulePreset.daily);
    expect(back.maxRunCount, 3);
    expect(back.effectiveMaxRunCount, 3);
  });

  test('copyWith sets and clears runAtMs', () {
    final a = Automation(
      id: 'a1',
      name: 'Once',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      preset: AutomationSchedulePreset.once,
      runAtMs: 1_700_000_100_000,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_100_000,
      enabled: true,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final changed = a.copyWith(runAtMs: 5);
    expect(changed.runAtMs, 5);
    expect(changed, isNot(a));
    final cleared = changed.copyWith(clearRunAtMs: true);
    expect(cleared.runAtMs, isNull);
    expect(cleared.preset, AutomationSchedulePreset.once);
    expect(a.copyWith(runAtMs: a.runAtMs), a);
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

  Automation runCommandAutomation({
    String command = 'echo hi',
    int timeoutSeconds = 300,
    AutomationCatchUpPolicy catchUpPolicy = AutomationCatchUpPolicy.none,
    String? sessionId,
    String? workingDirectoryPath,
  }) {
    return Automation(
      id: 'a1',
      name: 'nightly',
      action: AutomationAction.runCommand,
      workspaceId: 'ws1',
      command: command,
      timeoutSeconds: timeoutSeconds,
      catchUpPolicy: catchUpPolicy,
      sessionId: sessionId,
      workingDirectoryPath: workingDirectoryPath,
      message: '',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '02:00',
      timezone: 'Asia/Shanghai',
      dtstartMs: 1000,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    );
  }

  test('runCommand does not require a message', () {
    runCommandAutomation().validate();
  });

  test('runCommand rejects empty command', () {
    expect(
      () => runCommandAutomation(command: '  ').validate(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('runCommand rejects command over 2000 characters', () {
    expect(
      () => runCommandAutomation(command: 'a' * 2001).validate(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('runCommand rejects out-of-range timeoutSeconds', () {
    expect(
      () => runCommandAutomation(timeoutSeconds: 10).validate(),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => runCommandAutomation(timeoutSeconds: 1801).validate(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('runCommand rejects a bound session', () {
    expect(
      () => runCommandAutomation(sessionId: 's1').validate(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('runCommand json round-trips', () {
    final original = runCommandAutomation(
      command: 'npm ci && npm run build',
      timeoutSeconds: 900,
      catchUpPolicy: AutomationCatchUpPolicy.once,
    );
    final restored = Automation.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.isRunCommand, isTrue);
    expect(restored.timeoutSeconds, 900);
    expect(restored.catchUpPolicy, AutomationCatchUpPolicy.once);
  });

  test('runCommand json round-trips workingDirectoryPath', () {
    final original = runCommandAutomation(workingDirectoryPath: '/repo/sub');
    final json = original.toJson();
    expect(json['workingDirectoryPath'], '/repo/sub');
    final restored = Automation.fromJson(json);
    expect(restored.workingDirectoryPath, '/repo/sub');
    expect(restored, original);
  });

  test('legacy json without runCommand fields still parses', () {
    final json = <String, Object?>{
      'id': 'a1',
      'name': 'daily',
      'action': 'scheduledMessage',
      'workspaceId': 'ws1',
      'sessionId': 's1',
      'message': 'hi',
      'preset': 'daily',
      'hourMinute': '09:00',
      'timezone': 'Asia/Shanghai',
      'dtstartMs': 1000,
      'createdAtMs': 1000,
      'updatedAtMs': 1000,
    };
    final restored = Automation.fromJson(json);
    expect(restored.timeoutSeconds, 300);
    expect(restored.catchUpPolicy, AutomationCatchUpPolicy.none);
    expect(restored.command, isNull);
  });

  test('AutomationRun carries command result fields', () {
    const run = AutomationRun(
      id: 'r1',
      automationId: 'a1',
      workspaceId: 'ws1',
      scheduledForMs: 1000,
      status: AutomationRunStatus.failed,
      trigger: AutomationRunTrigger.scheduled,
      exitCode: 2,
      stdoutTail: 'out',
      stderrTail: 'err',
      outputTruncated: true,
      durationMs: 1234,
    );
    final restored = AutomationRun.fromJson(run.toJson());
    expect(restored, run);
    expect(restored.exitCode, 2);
    expect(restored.outputTruncated, isTrue);
    expect(restored.durationMs, 1234);
  });
}
