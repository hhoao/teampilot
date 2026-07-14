import 'package:teampilot/models/automation.dart';

Automation sampleAutomation({
  required String id,
  required String workspaceId,
  bool isPersonal = true,
  String? presetId = 'preset-1',
  String? teamId,
  String? sessionId,
}) {
  return Automation(
    id: id,
    name: 'Ping $id',
    action: sessionId == null
        ? AutomationAction.launchPrompt
        : AutomationAction.scheduledMessage,
    workspaceId: workspaceId,
    isPersonal: isPersonal,
    presetId: isPersonal ? presetId : null,
    teamId: !isPersonal ? teamId : null,
    sessionId: sessionId,
    message: 'hello',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}
