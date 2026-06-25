import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';

void main() {
  test('newSession uses local factory when target is local', () {
    var seenExecutable = '';
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) {
        seenExecutable = executable;
        return TerminalSession(executable: executable);
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
        return TerminalSession(executable: executable);
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
        sshProfileRepository: SshProfileRepository(),
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

    expect(session.runtimeTarget?.namespace.isSsh, isTrue);
    expect(session.validateLaunch, isFalse);
    expect(session.usesRemoteTransport, isTrue);
  });

  test('cliForMember resolves member-specific cli', () {
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) =>
          TerminalSession(executable: executable),
    );
    const team = TeamProfile(id: 't', name: 'T', members: []);

    expect(factory.cliForMember(team, 'missing'), team.cli);
  });
}
