import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_workspace.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';
import 'package:teampilot/utils/launch_identity_resolver.dart';

void main() {
  test('uses defaultIdentityId when identity exists', () {
    const workspace = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp/p1',
      createdAt: 0,
      defaultIdentityId: 'coding',
    );
    final personal = const PersonalIdentity(id: 'coding', display: 'Coding');
    final result = resolveWorkspaceLaunchIdentity(
      workspace,
      (id) => id == 'coding' ? personal : null,
    );
    expect(result, const LaunchIdentity('coding'));
  });

  test('dangling defaultIdentityId falls back to default personal', () {
    const workspace = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp/p1',
      createdAt: 0,
      defaultIdentityId: 'deleted-id',
    );
    final result = resolveWorkspaceLaunchIdentity(workspace, (_) => null);
    expect(
      result,
      const LaunchIdentity(IdentityProvisioner.defaultPersonalId),
    );
  });

  test('empty defaultIdentityId falls back to default personal', () {
    const workspace = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp/p1',
      createdAt: 0,
    );
    final result = resolveWorkspaceLaunchIdentity(workspace, (_) => null);
    expect(
      result,
      const LaunchIdentity(IdentityProvisioner.defaultPersonalId),
    );
  });
}
