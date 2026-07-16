import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/workspace/automation_launch_directory.dart';

Automation _launchAutomation({
  String? projectFolderPath,
  String? workingDirectoryPath,
}) {
  return Automation(
    id: 'a1',
    name: 'n',
    action: AutomationAction.launchPrompt,
    workspaceId: 'ws1',
    isPersonal: true,
    presetId: 'preset-1',
    projectFolderPath: projectFolderPath,
    workingDirectoryPath: workingDirectoryPath,
    message: 'hi',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 0,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

void main() {
  test('prefers workingDirectoryPath over projectFolderPath', () {
    final automation = _launchAutomation(
      projectFolderPath: '/repo',
      workingDirectoryPath: '/repo/feature',
    );
    expect(
      automationLaunchWorkingDirectory(automation),
      '/repo/feature',
    );
  });

  test('falls back to projectFolderPath', () {
    final automation = _launchAutomation(projectFolderPath: '/repo');
    expect(automationLaunchWorkingDirectory(automation), '/repo');
  });

  test('falls back to workspace first folder', () {
    final automation = _launchAutomation();
    final workspace = Workspace(
      workspaceId: 'ws1',
      folders: [WorkspaceFolder(path: '/default')],
      createdAt: 1,
    );
    expect(
      automationLaunchWorkingDirectory(automation, workspace: workspace),
      '/default',
    );
  });
}
