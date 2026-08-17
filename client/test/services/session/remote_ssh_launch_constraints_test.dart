import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';
import 'package:teampilot/services/session/remote_ssh_launch_constraints.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/ssh/ssh_member_session.dart';

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

    test(
      'bare-metal root rejects dangerous launch before returning a spec',
      () async {
        const member = TeamMemberConfig(
          id: 'member',
          name: 'Member',
          launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
        );
        final session = SshMemberSession.testing(
          profile: const SshProfile(
            id: 'ssh-1',
            name: 'SSH',
            host: 'example.com',
            username: 'root',
          ),
          client: _RootBareMetalClient(),
        );
        addTearDown(session.close);

        await expectLater(
          applyRemoteSshLaunchConstraints(
            spec: ShellLaunchSpec.teamMember(
              team: const TeamProfile(id: 'team', name: 'Team'),
              member: member,
            ),
            memberTarget: RuntimeTarget.ssh('ssh-1', label: 'SSH'),
            memberSession: session,
            profile: session.profile,
          ),
          throwsA(
            isA<CliLaunchCapabilityException>().having(
              (error) => error.contributionKey,
              'contributionKey',
              'remote-ssh-root-security',
            ),
          ),
        );
      },
    );

    test('unknown root status rejects dangerous launch closed', () async {
      const member = TeamMemberConfig(
        id: 'member',
        name: 'Member',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      );
      final session = SshMemberSession.testing(
        profile: const SshProfile(
          id: 'ssh-1',
          name: 'SSH',
          host: 'example.com',
          username: 'unknown',
        ),
        client: _RootBareMetalClient(idExitCode: 1),
      );
      addTearDown(session.close);

      await expectLater(
        applyRemoteSshLaunchConstraints(
          spec: ShellLaunchSpec.teamMember(
            team: const TeamProfile(id: 'team', name: 'Team'),
            member: member,
          ),
          memberTarget: RuntimeTarget.ssh('ssh-1', label: 'SSH'),
          memberSession: session,
          profile: session.profile,
        ),
        throwsA(
          isA<CliLaunchCapabilityException>().having(
            (error) => error.contributionKey,
            'contributionKey',
            'remote-ssh-root-security',
          ),
        ),
      );
    });
  });
}

class _RootBareMetalClient extends SSHClient {
  _RootBareMetalClient({this.idExitCode = 0})
    : super(_FakeSSHSocket(), username: 'root');

  final int idExitCode;

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    final output = command == 'id -u' ? '0' : '';
    return SSHRunResult(
      output: Uint8List.fromList(output.codeUnits),
      stdout: Uint8List.fromList(output.codeUnits),
      stderr: Uint8List(0),
      exitCode: command == 'id -u' ? idExitCode : 1,
      exitSignal: null,
    );
  }

  @override
  Future<void> ping() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    unawaited(_inputController.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
