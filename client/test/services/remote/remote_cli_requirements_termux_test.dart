import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/remote/remote_cli_requirements.dart';

void main() {
  test('remoteCliRequirementsForPlacement includes termux machine', () {
    const termuxTarget = RuntimeTarget(
      id: 'termux:default',
      label: 'Termux',
      kind: RuntimeKind.termux,
      sshProfileId: 'termux',
    );
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      cli: CliTool.claude,
      members: const [TeamMemberConfig(id: 'dev', name: 'Dev')],
      createdAt: 1,
    );
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: const [
        WorkspaceFolder(path: '/data', targetId: 'termux:default'),
      ],
      createdAt: 1,
    );
    final requirements = remoteCliRequirementsForPlacement(
      workspace: workspace,
      team: team,
      placement: const {
        'termux:default': {'dev': 1},
      },
      globalPresets: const <CliPreset>[],
      selectableTargets: const [termuxTarget],
    );
    expect(requirements, hasLength(1));
    expect(requirements.single.target.id, 'termux:default');
    expect(requirements.single.cli, CliTool.claude);
  });
}
