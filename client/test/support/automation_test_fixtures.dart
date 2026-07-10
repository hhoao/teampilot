import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/automation_tab_scope.dart';
import 'package:teampilot/models/launch_profile_kind.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/automation/automation_dispatcher.dart';

const simpleAutomationTabScope = AutomationTabScope(
  workspaceId: 'ws1',
  launchProfileId: AutomationTabScope.simpleLaunchProfileId,
);

AutomationLaunchProfileKindResolver testLaunchProfileKindResolver({
  String teamProfileId = 'team-1',
}) {
  return (profileId) {
    if (profileId == AutomationTabScope.simpleLaunchProfileId) {
      return null;
    }
    if (profileId == teamProfileId) return LaunchProfileKind.team;
    return LaunchProfileKind.team;
  };
}

Automation sampleAutomation({
  required String id,
  required String workspaceId,
  String launchProfileId = AutomationTabScope.simpleLaunchProfileId,
  String? sessionId,
}) {
  return Automation(
    id: id,
    name: 'Ping $id',
    action: sessionId == null
        ? AutomationAction.launchPrompt
        : AutomationAction.scheduledMessage,
    workspaceId: workspaceId,
    launchProfileId: launchProfileId,
    sessionId: sessionId,
    cli: sessionId == null ? CliTool.claude : null,
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

AutomationTabScope automationTabScopeFor({
  required String workspaceId,
  String launchProfileId = AutomationTabScope.simpleLaunchProfileId,
}) {
  return AutomationTabScope(
    workspaceId: workspaceId,
    launchProfileId: launchProfileId,
  );
}
