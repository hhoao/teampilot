import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/launch_security_policy.dart';

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

  test('launchPrompt serializes only the normalized security policy', () {
    const policy = LaunchSecurityPolicy(
      approval: LaunchApprovalPolicy.autoApprove,
      sandbox: LaunchSandboxPolicy.workspaceWrite,
      hookTrust: LaunchHookTrustPolicy.trustedOnly,
    );
    final automation = Automation(
      id: 'security',
      name: 'Secure launch',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws',
      isPersonal: true,
      presetId: 'preset-1',
      launchSecurityPolicy: policy,
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
    expect(json['launchSecurityPolicy'], policy.toJson());
    expect(json.containsKey('dangerouslySkipPermissions'), isFalse);
    expect(
      Automation.fromJson({
        ...json,
        'dangerouslySkipPermissions': true,
      }).launchSecurityPolicy,
      policy,
    );
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
}
