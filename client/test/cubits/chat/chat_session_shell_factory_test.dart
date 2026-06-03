import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  test('newSession uses local factory when not in ssh mode', () {
    var seenExecutable = '';
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) {
        seenExecutable = executable;
        return TerminalSession(executable: executable);
      },
      connectionModeResolver: () => ConnectionMode.localPty,
    );

    final session = factory.newSession(TeamCli.claude);

    expect(session, isA<TerminalSession>());
    expect(seenExecutable, 'exec-claude');
  });

  test('cliForMember resolves member-specific cli', () {
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) =>
          TerminalSession(executable: executable),
    );
    const team = TeamConfig(id: 't', name: 'T', members: []);

    expect(factory.cliForMember(team, 'missing'), team.cli);
  });
}
