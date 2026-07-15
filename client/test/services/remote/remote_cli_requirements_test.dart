import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/remote/remote_cli_requirements.dart';

void main() {
  const sshTarget = RuntimeTarget(
    id: 'ssh:host-a',
    label: 'Build host',
    kind: RuntimeKind.ssh,
    sshProfileId: 'host-a',
  );
  final localTarget = RuntimeTarget.local();

  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: [
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
    ],
    createdAt: 1,
  );

  final team = TeamProfile(
    id: 'team-1',
    name: 'Team',
    cli: CliTool.codex,
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'dev', name: 'Dev'),
    ],
    createdAt: 1,
  );

  test('collects distinct SSH target × CLI pairs from placement', () {
    final requirements = remoteCliRequirementsForPlacement(
      workspace: workspace,
      team: team,
      placement: {
        'ssh:host-a': {'dev': 1},
        'local': {'team-lead': 1},
      },
      globalPresets: const [],
      selectableTargets: [localTarget, sshTarget],
    );

    expect(requirements, hasLength(1));
    expect(requirements.single.target.id, 'ssh:host-a');
    expect(requirements.single.cli, CliTool.codex);
    expect(requirements.single.hostLabel, 'Build host');
  });

  test('ignores SSH targets not in selectableTargets', () {
    final requirements = remoteCliRequirementsForPlacement(
      workspace: workspace,
      team: team,
      placement: {'ssh:host-a': {'dev': 1}},
      globalPresets: const [],
      selectableTargets: [localTarget],
    );

    expect(requirements, isEmpty);
  });

  test('dedupes same target and CLI', () {
    final requirements = remoteCliRequirementsForPlacement(
      workspace: workspace,
      team: team,
      placement: {'ssh:host-a': {'dev': 2}},
      globalPresets: const [],
      selectableTargets: [localTarget, sshTarget],
    );

    expect(requirements, hasLength(1));
  });
}
