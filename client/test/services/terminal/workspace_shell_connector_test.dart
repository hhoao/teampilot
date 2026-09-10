import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/flashskyai/remote_flashskyai_command_builder.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkspaceShellConnector connector;

  setUp(() {
    connector = WorkspaceShellConnector(
      transportFactory: TerminalTransportFactory(
        sshProfileRepository: SshProfileRepository(),
        sshCredentialStore: InMemorySshCredentialStore(),
        sshKnownHostRepository: InMemorySshKnownHostRepository(),
      ),
      sshProfileRepository: SshProfileRepository(),
    );
  });

  group('WorkspaceShellConnector.resolveLaunchPlan', () {
    test('local spec uses resolved shell path and cwd', () {
      const requested = '/bin/bash';
      final plan = connector.resolveLaunchPlan(
        spec: WorkspaceTerminalLocalSpec(requested),
        workingDirectory: '/home/user/proj',
      );
      expect(File(plan.executable).existsSync(), isTrue);
      expect(plan.workingDirectory, '/home/user/proj');
      expect(plan.usesRemoteTransport, isFalse);
      expect(plan.runtimeTarget.kind.name, 'local');
    });

    test('ssh profile spec uses remote transport', () {
      final plan = connector.resolveLaunchPlan(
        spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
        workingDirectory: '/remote',
      );
      expect(plan.usesRemoteTransport, isTrue);
      expect(plan.executable, HostInteractiveShell.remotePosixExecutable);
      expect(plan.runtimeTarget.kind.name, 'ssh');
    });
  });

  group('WorkspaceShellConnector.runtimeTargetFor', () {
    test('maps workspace target id to runtime kind', () {
      final target = connector.runtimeTargetFor(
        const WorkspaceTerminalWorkspaceTargetSpec('wsl:Ubuntu'),
      );
      expect(target.kind.name, 'wsl');
      expect(target.wslDistro, 'Ubuntu');
    });
  });

  group('WorkspaceShellConnector.buildShellRemoteCommand', () {
    test('embedded profile sends a bare shell request (no command)', () {
      const profile = SshProfile(
        id: 'e1',
        name: 'desktop',
        host: '127.0.0.1',
        username: 'u',
        embeddedTarget: true,
      );

      expect(
        WorkspaceShellConnector.buildShellRemoteCommand(
          profile: profile,
          executable: HostInteractiveShell.remotePosixExecutable,
          arguments: const ['-l'],
          workingDirectory: '/remote',
          useLoginShell: true,
        ),
        isNull,
      );
    });

    test('legacy profile keeps the pre-codec POSIX login-shell command', () {
      const profile = SshProfile(
        id: 'p1',
        name: 'box',
        host: '127.0.0.1',
        username: 'u',
      );

      final command = WorkspaceShellConnector.buildShellRemoteCommand(
        profile: profile,
        executable: HostInteractiveShell.remotePosixExecutable,
        arguments: const ['-l'],
        workingDirectory: '/remote',
        useLoginShell: true,
      );

      expect(command, startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '));
      // Byte-for-byte what the code built before the codec existed.
      expect(
        command,
        RemoteFlashskyaiCommandBuilder().buildCommand(
          remoteExecutablePath: HostInteractiveShell.remotePosixExecutable,
          arguments: const ['-l'],
          workingDirectory: '/remote',
          useLoginShell: true,
        ),
      );
    });
  });
}
