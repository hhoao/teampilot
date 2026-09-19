import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/cli/flashskyai/remote_flashskyai_command_builder.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('newSession uses local factory when target is local', () {
    var seenExecutable = '';
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) {
        seenExecutable = executable;
        return TerminalSession(
          executable: executable,
          fs: InMemoryFilesystem(),
        );
      },
      defaultTargetResolver: RuntimeTarget.local,
    );

    final session = factory.newSession(CliTool.claude);

    expect(session, isA<TerminalSession>());
    expect(seenExecutable, 'exec-claude');
  });

  test('newSession uses local factory when target is ssh but no profile', () {
    var seenExecutable = '';
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) {
        seenExecutable = executable;
        return TerminalSession(
          executable: executable,
          fs: InMemoryFilesystem(),
        );
      },
      // ssh kind but no transportFactory/profile → falls back to local PTY,
      // matching the legacy connectionMode==ssh-without-profile behavior.
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
    );

    final session = factory.newSession(CliTool.claude);

    expect(session, isA<TerminalSession>());
    expect(seenExecutable, 'exec-claude');
  });

  test('newSession uses ssh transport when workTarget is ssh with profile', () {
    const profile = SshProfile(
      id: 'p1',
      name: 'box',
      host: '127.0.0.1',
      port: 22,
      username: 'u',
    );
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'claude',
      transportFactory: TerminalTransportFactory(
        sshProfileRepository: SshProfileRepository(storage: fakeHomeStorage()),
        sshCredentialStore: InMemorySshCredentialStore(),
        sshKnownHostRepository: InMemorySshKnownHostRepository(),
      ),
      sshProfileById: (id) => id == 'p1' ? profile : null,
      defaultTargetResolver: RuntimeTarget.local,
    );

    final session = factory.newSession(
      CliTool.claude,
      workTarget: RuntimeTarget.ssh('p1', label: 'box'),
    );

    expect(session.runtimeTarget.namespace.isSsh, isTrue);
    expect(session.validateLaunch, isFalse);
    expect(session.usesRemoteTransport, isTrue);
  });

  test('cliForMember resolves member-specific cli', () {
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      terminalSessionFactory:
          ({required executable, scrollbackLines = 10000}) =>
              TerminalSession(executable: executable, fs: InMemoryFilesystem()),
    );
    const team = TeamProfile(id: 't', name: 'T', members: []);

    expect(factory.cliForMember(team, 'missing'), team.cli);
  });

  test('newSession uses Cursor 45s startup deadline', () {
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'cursor-agent',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      defaultTargetResolver: RuntimeTarget.local,
    );

    final session = factory.newSession(CliTool.cursor);

    expect(session.startupDeadline, const Duration(seconds: 45));
  });

  test('newSession keeps custom factory sessions for Cursor', () {
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'cursor-agent',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      terminalSessionFactory:
          ({required executable, scrollbackLines = 10000}) =>
              _RunningFakeShell(executable: executable),
      defaultTargetResolver: RuntimeTarget.local,
    );

    final session = factory.newSession(CliTool.cursor);

    expect(session, isA<_RunningFakeShell>());
    expect(session.isRunning, isTrue);
  });

  group('ChatSessionShellFactory.buildMemberRemoteCommand', () {
    test('embedded profile gets a tp1: structured exec payload', () {
      const profile = SshProfile(
        id: 'p1',
        name: 'desktop',
        host: '127.0.0.1',
        username: 'u',
        embeddedTarget: true,
      );

      final command = ChatSessionShellFactory.buildMemberRemoteCommand(
        profile: profile,
        executable: 'claude',
        arguments: const ['--resume', 's1'],
        remoteWorkingDirectory: '/remote/work',
        environment: const {'K': 'V'},
        useLoginShell: true,
      );

      expect(
        command,
        'tp1:{"argv":["claude","--resume","s1"],'
        '"cwd":"/remote/work","env":{"K":"V"}}',
      );
    });

    test('embedded payload omits cwd and env when empty', () {
      const profile = SshProfile(
        id: 'p1',
        name: 'desktop',
        host: '127.0.0.1',
        username: 'u',
        embeddedTarget: true,
      );

      final command = ChatSessionShellFactory.buildMemberRemoteCommand(
        profile: profile,
        executable: 'claude',
        arguments: const [],
        remoteWorkingDirectory: '',
        environment: const {},
        useLoginShell: false,
      );

      expect(command, 'tp1:{"argv":["claude"]}');
    });

    test('legacy profile keeps the pre-codec login-shell command', () {
      const profile = SshProfile(
        id: 'p1',
        name: 'box',
        host: '127.0.0.1',
        username: 'u',
      );

      final command = ChatSessionShellFactory.buildMemberRemoteCommand(
        profile: profile,
        executable: 'claude',
        arguments: const ['--resume', 's1'],
        remoteWorkingDirectory: '/remote/work',
        environment: const {'K': 'V'},
        useLoginShell: true,
      );

      expect(command, startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '));
      // Byte-for-byte what the code built before the codec existed.
      expect(
        command,
        RemoteFlashskyaiCommandBuilder().buildCommand(
          remoteExecutablePath: 'claude',
          arguments: const ['--resume', 's1'],
          workingDirectory: '/remote/work',
          environment: const {'K': 'V'},
          useLoginShell: true,
        ),
      );
    });
  });
}

class _RunningFakeShell extends TerminalSession {
  _RunningFakeShell({required super.executable})
    : super(fs: InMemoryFilesystem());

  @override
  bool get isRunning => true;
}
