import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_shell.dart';

AppProject _project({
  required String id,
  String teamId = '',
  String display = 'my-app',
  String primaryPath = '/home/user/my-app',
}) {
  return AppProject(
    projectId: id,
    primaryPath: primaryPath,
    teamId: teamId,
    display: display,
    createdAt: 1,
  );
}

void main() {
  test('personal tooltip prefixes kind label', () {
    final tooltip = HomeWorkspaceShell.formatProjectTabTooltip(
      project: _project(id: 'p1', teamId: '', display: 'solo'),
      personalKindLabel: 'Personal',
      teamName: null,
    );
    expect(tooltip, 'Personal · solo\n/home/user/my-app');
  });

  test('team tooltip uses team name prefix', () {
    final tooltip = HomeWorkspaceShell.formatProjectTabTooltip(
      project: _project(id: 't1', teamId: 'team-1', display: 'shared'),
      personalKindLabel: 'Personal',
      teamName: 'Alpha Team',
    );
    expect(tooltip, 'Alpha Team · shared\n/home/user/my-app');
  });

  test('team tooltip falls back to teamId when name missing', () {
    final tooltip = HomeWorkspaceShell.formatProjectTabTooltip(
      project: _project(id: 't1', teamId: 'team-1', display: 'shared'),
      personalKindLabel: 'Personal',
      teamName: null,
    );
    expect(tooltip, 'team-1 · shared\n/home/user/my-app');
  });

  test('omits path line when empty or same as display name', () {
    expect(
      HomeWorkspaceShell.formatProjectTabTooltip(
        project: _project(
          id: 'p1',
          display: 'solo',
          primaryPath: '',
        ),
        personalKindLabel: 'Personal',
        teamName: null,
      ),
      'Personal · solo',
    );
  });
}
