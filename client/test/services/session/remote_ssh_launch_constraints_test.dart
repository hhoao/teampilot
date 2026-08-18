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
  group('remoteSshRunsAsRoot', () {
    test(
      'returns true only for uid 0 and false for valid nonzero uid',
      () async {
        final rootSession = SshMemberSession.testing(
          profile: const SshProfile(
            id: 'ssh-root',
            name: 'SSH',
            host: 'example.com',
            username: 'root',
          ),
          client: _RootBareMetalClient(idOutput: '0'),
        );
        final userSession = SshMemberSession.testing(
          profile: const SshProfile(
            id: 'ssh-user',
            name: 'SSH',
            host: 'example.com',
            username: 'user',
          ),
          client: _RootBareMetalClient(idOutput: '1000'),
        );
        addTearDown(rootSession.close);
        addTearDown(userSession.close);

        expect(await remoteSshRunsAsRoot(memberSession: rootSession), isTrue);
        expect(await remoteSshRunsAsRoot(memberSession: userSession), isFalse);
      },
    );

    test('returns null for empty or malformed uid output', () async {
      final emptySession = SshMemberSession.testing(
        profile: const SshProfile(
          id: 'ssh-empty',
          name: 'SSH',
          host: 'example.com',
          username: 'unknown',
        ),
        client: _RootBareMetalClient(idOutput: ''),
      );
      final malformedSession = SshMemberSession.testing(
        profile: const SshProfile(
          id: 'ssh-malformed',
          name: 'SSH',
          host: 'example.com',
          username: 'unknown',
        ),
        client: _RootBareMetalClient(idOutput: 'not-a-uid'),
      );
      addTearDown(emptySession.close);
      addTearDown(malformedSession.close);

      expect(await remoteSshRunsAsRoot(memberSession: emptySession), isNull);
      expect(
        await remoteSshRunsAsRoot(memberSession: malformedSession),
        isNull,
      );
    });
  });

  group('remoteSshInDockerContainer', () {
    test(
      'distinguishes confirmed container and non-container results',
      () async {
        final containerSession = SshMemberSession.testing(
          profile: const SshProfile(
            id: 'ssh-container',
            name: 'SSH',
            host: 'example.com',
            username: 'root',
          ),
          client: _RootBareMetalClient(dockerExitCode: 0),
        );
        final nonContainerSession = SshMemberSession.testing(
          profile: const SshProfile(
            id: 'ssh-host',
            name: 'SSH',
            host: 'example.com',
            username: 'root',
          ),
          client: _RootBareMetalClient(dockerExitCode: 1),
        );
        addTearDown(containerSession.close);
        addTearDown(nonContainerSession.close);

        expect(
          await remoteSshInDockerContainer(memberSession: containerSession),
          RemoteSshDockerStatus.confirmedContainer,
        );
        expect(
          await remoteSshInDockerContainer(memberSession: nonContainerSession),
          RemoteSshDockerStatus.confirmedNonContainer,
        );
      },
    );

    test('returns unknown when the Docker probe fails unexpectedly', () async {
      final session = SshMemberSession.testing(
        profile: const SshProfile(
          id: 'ssh-unknown',
          name: 'SSH',
          host: 'example.com',
          username: 'root',
        ),
        client: _RootBareMetalClient(dockerExitCode: 2),
      );
      addTearDown(session.close);

      expect(
        await remoteSshInDockerContainer(memberSession: session),
        RemoteSshDockerStatus.unknown,
      );
    });

    test('returns unknown when the Docker probe throws', () async {
      final session = SshMemberSession.testing(
        profile: const SshProfile(
          id: 'ssh-error',
          name: 'SSH',
          host: 'example.com',
          username: 'root',
        ),
        client: _RootBareMetalClient(throwOnDockerProbe: true),
      );
      addTearDown(session.close);

      expect(
        await remoteSshInDockerContainer(memberSession: session),
        RemoteSshDockerStatus.unknown,
      );
    });
  });

  group('resolveRemoteRootSecurityPolicy', () {
    test('dangerous SSH launch rejects a missing member session', () async {
      const member = TeamMemberConfig(
        id: 'member',
        name: 'Member',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      );

      await expectLater(
        applyRemoteSshLaunchConstraints(
          spec: ShellLaunchSpec.teamMember(
            team: const TeamProfile(id: 'team', name: 'Team'),
            member: member,
          ),
          memberTarget: RuntimeTarget.ssh('ssh-1', label: 'SSH'),
          memberSession: null,
          profile: const SshProfile(
            id: 'ssh-1',
            name: 'SSH',
            host: 'example.com',
            username: 'root',
          ),
        ),
        throwsA(
          isA<CliLaunchCapabilityException>().having(
            (error) => error.contributionKey,
            'contributionKey',
            'remote-ssh-security-prerequisites',
          ),
        ),
      );
    });

    test('dangerous SSH launch rejects a missing SSH profile', () async {
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
          profile: null,
        ),
        throwsA(
          isA<CliLaunchCapabilityException>().having(
            (error) => error.contributionKey,
            'contributionKey',
            'remote-ssh-security-prerequisites',
          ),
        ),
      );
    });

    test('unchanged when safe policy or non-root', () {
      expect(
        resolveRemoteRootSecurityPolicy(
          securityPolicy: LaunchSecurityPolicy.cliDefault,
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

    test('empty root probe output rejects dangerous launch closed', () async {
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
        client: _RootBareMetalClient(idOutput: ''),
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
        throwsA(isA<CliLaunchCapabilityException>()),
      );
    });

    test(
      'malformed root probe output rejects dangerous launch closed',
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
            username: 'unknown',
          ),
          client: _RootBareMetalClient(idOutput: 'not-a-uid'),
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
          throwsA(isA<CliLaunchCapabilityException>()),
        );
      },
    );

    test(
      'probe exception rejects dangerous launch with typed reason',
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
            username: 'unknown',
          ),
          client: _RootBareMetalClient(throwOnIdProbe: true),
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
              (error) => error.reason,
              'reason',
              contains('id -u'),
            ),
          ),
        );
      },
    );
    test(
      'Docker probe exception rejects dangerous root launch with typed error',
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
          client: _RootBareMetalClient(throwOnDockerProbe: true),
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
            isA<CliLaunchCapabilityException>()
                .having(
                  (error) => error.contributionKey,
                  'contributionKey',
                  'remote-ssh-container-security',
                )
                .having((error) => error.reason, 'reason', contains('Docker')),
          ),
        );
      },
    );
  });
}

class _RootBareMetalClient extends SSHClient {
  _RootBareMetalClient({
    this.idExitCode = 0,
    this.idOutput = '0',
    this.throwOnIdProbe = false,
    this.dockerExitCode = 1,
    this.throwOnDockerProbe = false,
  }) : super(_FakeSSHSocket(), username: 'root');

  final int idExitCode;
  final String idOutput;
  final bool throwOnIdProbe;
  final int dockerExitCode;
  final bool throwOnDockerProbe;

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
    if (command == 'id -u' && throwOnIdProbe) {
      throw StateError('transport disconnected');
    }
    if (command == 'test -f /.dockerenv' && throwOnDockerProbe) {
      throw StateError('Docker probe transport disconnected');
    }
    final output = command == 'id -u' ? idOutput : '';
    final exitCode = switch (command) {
      'id -u' => idExitCode,
      'test -f /.dockerenv' => dockerExitCode,
      _ => 1,
    };
    return SSHRunResult(
      output: Uint8List.fromList(output.codeUnits),
      stdout: Uint8List.fromList(output.codeUnits),
      stderr: Uint8List(0),
      exitCode: exitCode,
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
