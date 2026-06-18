import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_workspace.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_shell.dart';

Workspace _workspace({
  required String id,
  String display = 'my-app',
  String primaryPath = '/home/user/my-app',
}) {
  return Workspace(
    workspaceId: id,
    primaryPath: primaryPath,
    display: display,
    createdAt: 1,
  );
}

void main() {
  test('personal tooltip prefixes kind label', () {
    final tooltip = HomeShell.formatWorkspaceTabTooltip(
      workspace: _workspace(id: 'p1', display: 'solo'),
      personalKindLabel: 'Personal',
      isPersonal: true,
      teamName: null,
    );
    expect(tooltip, 'Personal · solo\n/home/user/my-app');
  });

  test('team tooltip uses team name prefix', () {
    final tooltip = HomeShell.formatWorkspaceTabTooltip(
      workspace: _workspace(id: 't1', display: 'shared'),
      personalKindLabel: 'Personal',
      isPersonal: false,
      teamName: 'Alpha Team',
      teamId: 'team-1',
    );
    expect(tooltip, 'Alpha Team · shared\n/home/user/my-app');
  });

  test('team tooltip falls back to teamId when name missing', () {
    final tooltip = HomeShell.formatWorkspaceTabTooltip(
      workspace: _workspace(id: 't1', display: 'shared'),
      personalKindLabel: 'Personal',
      isPersonal: false,
      teamName: null,
      teamId: 'team-1',
    );
    expect(tooltip, 'team-1 · shared\n/home/user/my-app');
  });

  test('omits path line when empty or same as display name', () {
    expect(
      HomeShell.formatWorkspaceTabTooltip(
        workspace: _workspace(
          id: 'p1',
          display: 'solo',
          primaryPath: '',
        ),
        personalKindLabel: 'Personal',
        isPersonal: true,
        teamName: null,
      ),
      'Personal · solo',
    );
  });
}
