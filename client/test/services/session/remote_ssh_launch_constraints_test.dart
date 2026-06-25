import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/remote_ssh_launch_constraints.dart';

void main() {
  group('resolveRemoteRootSkipPermissionsPolicy', () {
    test('unchanged when skip-permissions off or non-root', () {
      expect(
        resolveRemoteRootSkipPermissionsPolicy(
          skipPermissionsRequested: false,
          runsAsRoot: true,
          remoteInDocker: true,
        ),
        RemoteRootSkipPermissionsPolicy.unchanged,
      );
      expect(
        resolveRemoteRootSkipPermissionsPolicy(
          skipPermissionsRequested: true,
          runsAsRoot: false,
          remoteInDocker: false,
        ),
        RemoteRootSkipPermissionsPolicy.unchanged,
      );
    });

    test('container root injects IS_SANDBOX per Claude setup.ts', () {
      expect(
        resolveRemoteRootSkipPermissionsPolicy(
          skipPermissionsRequested: true,
          runsAsRoot: true,
          remoteInDocker: true,
        ),
        RemoteRootSkipPermissionsPolicy.injectSandboxEnv,
      );
    });

    test('bare-metal root drops flag', () {
      expect(
        resolveRemoteRootSkipPermissionsPolicy(
          skipPermissionsRequested: true,
          runsAsRoot: true,
          remoteInDocker: false,
        ),
        RemoteRootSkipPermissionsPolicy.dropFlag,
      );
    });
  });
}
