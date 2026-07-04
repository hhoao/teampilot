import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/services/automation/automation_launch_session_binding.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

Automation _launchPrompt({bool reuseSession = false, String? sessionId}) {
  return Automation(
    id: 'a1',
    name: 'Daily',
    action: AutomationAction.launchPrompt,
    workspaceId: 'ws1',
    launchProfileId: LaunchProfileProvisioner.defaultPersonalId,
    cliPresetId: 'preset-1',
    message: 'ping',
    reuseSession: reuseSession,
    sessionId: sessionId,
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  test('applyAfterSuccessfulDispatch binds session when reuse is on', () {
    final result = AutomationLaunchSessionBinding.applyAfterSuccessfulDispatch(
      _launchPrompt(reuseSession: true),
      sessionId: 'sess-bound',
    );
    expect(result.sessionId, 'sess-bound');
  });

  test('applyAfterSuccessfulDispatch ignores binding when reuse is off', () {
    final result = AutomationLaunchSessionBinding.applyAfterSuccessfulDispatch(
      _launchPrompt(reuseSession: false),
      sessionId: 'sess-new',
    );
    expect(result.sessionId, isNull);
  });

  test('stripWhenReuseDisabled clears an existing binding', () {
    final stripped = AutomationLaunchSessionBinding.stripWhenReuseDisabled(
      _launchPrompt(reuseSession: false, sessionId: 'sess-old'),
    );
    expect(stripped.sessionId, isNull);
  });

  test('onBoundSessionRemoved disables scheduled messages', () {
    final scheduled = Automation(
      id: 's1',
      name: 'Reset',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      launchProfileId: 'team-1',
      sessionId: 'sess-1',
      message: '/clear',
      preset: AutomationSchedulePreset.hourly,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: true,
      nextRunAtMs: 99,
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    final next = AutomationLaunchSessionBinding.onBoundSessionRemoved(
      scheduled,
    );
    expect(next.enabled, isFalse);
    expect(next.nextRunAtMs, isNull);
    expect(next.sessionId, 'sess-1');
  });

  test('onBoundSessionRemoved unbinds reusable launch prompts', () {
    final next = AutomationLaunchSessionBinding.onBoundSessionRemoved(
      _launchPrompt(reuseSession: true, sessionId: 'sess-1'),
    );
    expect(next.sessionId, isNull);
    expect(next.enabled, isTrue);
  });
}
