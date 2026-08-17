import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/session/remote_ssh_launch_constraints.dart';

void main() {
  group('resolveRemoteRootSecurityPolicy', () {
    test('unchanged when safe policy or non-root', () {
      expect(
        resolveRemoteRootSecurityPolicy(
          securityPolicy: const LaunchSecurityPolicy(),
          runsAsRoot: true,
          remoteInDocker: true,
        ),
        RemoteRootSecurityPolicy.unchanged,
      );
      expect(
        resolveRemoteRootSecurityPolicy(
          securityPolicy: LaunchSecurityPolicy.fullAccess,
          runsAsRoot: false,
          remoteInDocker: false,
        ),
        RemoteRootSecurityPolicy.unchanged,
      );
    });

    test('container root injects IS_SANDBOX per Claude setup.ts', () {
      expect(
        resolveRemoteRootSecurityPolicy(
          securityPolicy: LaunchSecurityPolicy.fullAccess,
          runsAsRoot: true,
          remoteInDocker: true,
        ),
        RemoteRootSecurityPolicy.injectSandboxEnv,
      );
    });

    test('bare-metal root drops flag unless target opt-in', () {
      expect(
        resolveRemoteRootSecurityPolicy(
          securityPolicy: LaunchSecurityPolicy.fullAccess,
          runsAsRoot: true,
          remoteInDocker: false,
        ),
        RemoteRootSecurityPolicy.dropDangerousPolicy,
      );
      expect(
        resolveRemoteRootSecurityPolicy(
          securityPolicy: LaunchSecurityPolicy.fullAccess,
          runsAsRoot: true,
          remoteInDocker: false,
          injectRootSandboxEnv: true,
        ),
        RemoteRootSecurityPolicy.injectSandboxEnv,
      );
    });
  });
}
