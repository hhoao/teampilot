import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/launch_profile_resolver.dart';

void main() {
  test('uses defaultProfileId when identity exists', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: const [WorkspaceFolder(path: '/tmp/p1')],
      createdAt: 0,
      defaultProfileId: 'coding',
    );
    final personal = const PersonalProfile(id: 'coding', display: 'Coding');
    final result = resolveWorkspaceLaunchProfileRef(
      workspace,
      (id) => id == 'coding' ? personal : null,
    );
    expect(result, const LaunchProfileRef('coding'));
  });

  test('dangling defaultProfileId falls back to default personal', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: const [WorkspaceFolder(path: '/tmp/p1')],
      createdAt: 0,
      defaultProfileId: 'deleted-id',
    );
    final result = resolveWorkspaceLaunchProfileRef(workspace, (_) => null);
    expect(
      result,
      const LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId),
    );
  });

  test('empty defaultProfileId falls back to default personal', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: const [WorkspaceFolder(path: '/tmp/p1')],
      createdAt: 0,
    );
    final result = resolveWorkspaceLaunchProfileRef(workspace, (_) => null);
    expect(
      result,
      const LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId),
    );
  });
}
