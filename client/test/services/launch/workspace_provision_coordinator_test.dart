import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/launch/workspace_provision_coordinator.dart';
import 'package:teampilot/services/launch/workspace_provisioner.dart';
import 'package:teampilot/services/storage/work_target_canonicalizer.dart';

void main() {
  final sshHome = RuntimeTarget.ssh('p1', label: 'box');

  WorkspaceProvisionCoordinator makeCoordinator() {
    return WorkspaceProvisionCoordinator(
      provisioner: _FakeWorkspaceProvisioner(),
      homeTarget: () => sshHome,
    );
  }

  test('isOffHome is false when member resolves to same ssh home', () {
    final coordinator = makeCoordinator();
    expect(coordinator.isOffHome(RuntimeTarget.local()), isFalse);
    expect(
      coordinator.isOffHome(WorkTargetCanonicalizer.fromId('local')),
      isFalse,
    );
    expect(coordinator.isOffHome(sshHome), isFalse);
  });

  test('isOffHome is true when member resolves to different ssh host', () {
    final coordinator = makeCoordinator();
    final other = RuntimeTarget.ssh('other', label: 'other');
    expect(coordinator.isOffHome(other), isTrue);
  });
}

class _FakeWorkspaceProvisioner implements WorkspaceProvisioner {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
