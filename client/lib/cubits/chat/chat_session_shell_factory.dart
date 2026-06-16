import '../../models/connection_mode.dart';
import '../../models/launch_target.dart';
import '../../models/team_config.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import 'model/chat_state.dart';

/// Builds [TerminalSession]s with the right executable / transport for the
/// active connection mode. Pure factory — owns no ChatState.
class ChatSessionShellFactory {
  ChatSessionShellFactory({
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TerminalSessionFactory terminalSessionFactory =
        defaultTerminalSessionFactory,
    TerminalTransportFactory? transportFactory,
    SshActiveProfileResolver? sshProfileResolver,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    ConnectionMode Function()? connectionModeResolver,
    int Function()? terminalScrollbackLinesResolver,
  }) : _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _terminalSessionFactory = terminalSessionFactory,
       _transportFactory = transportFactory,
       _sshProfileResolver = sshProfileResolver,
       _sshDefaultWorkingDirectoryResolver = sshDefaultWorkingDirectoryResolver,
       _sshUseLoginShellResolver = sshUseLoginShellResolver,
       _connectionModeResolver = connectionModeResolver,
       _terminalScrollbackLinesResolver = terminalScrollbackLinesResolver;

  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final TerminalSessionFactory _terminalSessionFactory;
  final TerminalTransportFactory? _transportFactory;
  final SshActiveProfileResolver? _sshProfileResolver;
  final String Function()? _sshDefaultWorkingDirectoryResolver;
  final bool Function()? _sshUseLoginShellResolver;
  final ConnectionMode Function()? _connectionModeResolver;
  final int Function()? _terminalScrollbackLinesResolver;

  ConnectionMode get _connectionMode =>
      _connectionModeResolver?.call() ?? ConnectionMode.localPty;

  bool get _useSsh =>
      _connectionMode == ConnectionMode.ssh &&
      _transportFactory != null &&
      _sshProfileResolver != null &&
      _sshProfileResolver() != null;

  int get _scrollbackLines => _terminalScrollbackLinesResolver?.call() ?? 10000;

  String _resolveExecutableFor(CliTool cli) =>
      _cliExecutableResolver?.call(cli) ?? _executableResolver();

  CliTool cliForMember(TeamConfig team, String memberId) {
    for (final m in team.members) {
      if (m.id == memberId) return m.cliWithin(team);
    }
    return team.cli;
  }

  TerminalSession newSession([CliTool cli = CliTool.claude]) {
    final executable = _resolveExecutableFor(cli);
    final scrollback = _scrollbackLines;
    if (_useSsh) {
      final profile = _sshProfileResolver?.call();
      if (profile == null) {
        return _terminalSessionFactory(
          executable: executable,
          scrollbackLines: scrollback,
        );
      }
      return TerminalSession(
        executable: executable,
        scrollbackLines: scrollback,
        validateLaunch: false,
        parseExecutable: false,
        transportStarter:
            (
              String executable, {
              required List<String> arguments,
              required String workingDirectory,
              required int columns,
              required int rows,
              Map<String, String>? environment,
            }) async {
              final remoteEnvironment = <String, String>{
                if (environment != null) ...environment,
              };
              final remoteWorkingDirectory = workingDirectory.isNotEmpty
                  ? workingDirectory
                  : (_sshDefaultWorkingDirectoryResolver?.call() ?? '');
              return _transportFactory!.startTransport(
                LaunchTarget.ssh(
                  sshProfileId: profile.id,
                  remoteExecutable: executable,
                  remoteWorkingDirectory: remoteWorkingDirectory,
                  remoteEnvironment: remoteEnvironment,
                  useLoginShell: _sshUseLoginShellResolver?.call() ?? false,
                ),
                arguments: arguments,
                columns: columns,
                rows: rows,
              );
            },
      );
    }
    return _terminalSessionFactory(
      executable: executable,
      scrollbackLines: scrollback,
    );
  }
}
