import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

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
