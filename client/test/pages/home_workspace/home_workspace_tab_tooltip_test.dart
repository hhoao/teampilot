import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/pages/home_workspace/open_workspace_tab_actions.dart';
import 'package:teampilot/theme/workspace_topology_colors.dart';

Workspace _workspace({
  required String id,
  String display = 'my-app',
  String primaryPath = '/home/user/my-app',
}) {
  return Workspace(
    workspaceId: id,
    folders: [WorkspaceFolder(path: primaryPath)],
    display: display,
    createdAt: 1,
  );
}

void main() {
  test('personal tooltip prefixes kind label', () {
    final tooltip = formatWorkspaceTabTooltip(
      workspace: _workspace(id: 'p1', display: 'solo'),
      personalKindLabel: 'Personal',
      isPersonal: true,
      teamName: null,
    );
    expect(tooltip, 'Personal · solo\n/home/user/my-app');
  });

  test('team tooltip uses team name prefix', () {
    final tooltip = formatWorkspaceTabTooltip(
      workspace: _workspace(id: 't1', display: 'shared'),
      personalKindLabel: 'Personal',
      isPersonal: false,
      teamName: 'Alpha Team',
      teamId: 'team-1',
    );
    expect(tooltip, 'Alpha Team · shared\n/home/user/my-app');
  });

  test('team tooltip falls back to teamId when name missing', () {
    final tooltip = formatWorkspaceTabTooltip(
      workspace: _workspace(id: 't1', display: 'shared'),
      personalKindLabel: 'Personal',
      isPersonal: false,
      teamName: null,
      teamId: 'team-1',
    );
    expect(tooltip, 'team-1 · shared\n/home/user/my-app');
  });

  test('omits path lines when every folder path is empty', () {
    expect(
      formatWorkspaceTabTooltip(
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

  test('lists every folder path on separate lines', () {
    final workspace = Workspace(
      workspaceId: 'mix',
      folders: const [
        WorkspaceFolder(path: '/home/user/app'),
        WorkspaceFolder(path: '/var/www', targetId: 'ssh:profile-1'),
      ],
      display: 'mixed-app',
      createdAt: 1,
    );
    final tooltip = formatWorkspaceTabTooltip(
      workspace: workspace,
      personalKindLabel: 'Personal',
      isPersonal: true,
      teamName: null,
      topology: WorkspaceTopology.mixed,
      topologyLabel: 'Mixed workspace',
    );
    expect(
      tooltip,
      'Mixed workspace · Personal · mixed-app\n'
      '/home/user/app\n'
      'SSH: /var/www',
    );
  });

  test('remote tooltip prefixes topology label and ssh path', () {
    final workspace = Workspace(
      workspaceId: 'r1',
      folders: [
        WorkspaceFolder(path: '/var/www', targetId: 'ssh:profile-1'),
      ],
      display: 'shared',
      createdAt: 1,
    );
    final tooltip = formatWorkspaceTabTooltip(
      workspace: workspace,
      personalKindLabel: 'Personal',
      isPersonal: false,
      teamName: 'Alpha Team',
      topology: WorkspaceTopology.remote,
      topologyLabel: 'Remote workspace',
    );
    expect(tooltip, 'Remote workspace · Alpha Team · shared\nSSH: /var/www');
  });

  test('formatWorkspaceFolderTooltipLine prefixes ssh targets', () {
    expect(
      formatWorkspaceFolderTooltipLine(
        const WorkspaceFolder(path: '/var/www', targetId: 'ssh:host'),
      ),
      'SSH: /var/www',
    );
    expect(
      formatWorkspaceFolderTooltipLine(
        const WorkspaceFolder(path: '/home/user/app'),
      ),
      '/home/user/app',
    );
  });

  test('homeWorkspaceTabBarColor uses topology accent for remote tabs', () {
    final scheme = ThemeData.light().colorScheme;
    final base = WorkspaceTopologyColors.of(
      topology: WorkspaceTopology.remote,
      colorScheme: scheme,
      brightness: Brightness.light,
    );
    final bar = homeWorkspaceTabBarColor(
      colorScheme: scheme,
      brightness: Brightness.light,
      topology: WorkspaceTopology.remote,
      active: true,
      hovered: false,
    );
    expect(bar, base.withValues(alpha: 1));
  });
}
