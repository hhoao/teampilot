import '../../models/runtime_target.dart' as rt;
import '../../models/runtime_target.dart' show RuntimeKind, sshProfileIdOfId;
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../services/session/remote_flashskyai_command_builder.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/terminal/ssh_pty_transport.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../services/workspace_dnd/runtime_target.dart';
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
    SshProfileByIdResolver? sshProfileById,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    rt.RuntimeTarget Function()? defaultTargetResolver,
    int Function()? terminalScrollbackLinesResolver,
  }) : _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _terminalSessionFactory = terminalSessionFactory,
       _transportFactory = transportFactory,
       _sshProfileResolver = sshProfileResolver,
       _sshProfileById = sshProfileById,
       _sshDefaultWorkingDirectoryResolver = sshDefaultWorkingDirectoryResolver,
       _sshUseLoginShellResolver = sshUseLoginShellResolver,
       _defaultTargetResolver = defaultTargetResolver,
       _terminalScrollbackLinesResolver = terminalScrollbackLinesResolver;

  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final TerminalSessionFactory _terminalSessionFactory;
  final TerminalTransportFactory? _transportFactory;
  final SshActiveProfileResolver? _sshProfileResolver;
  final SshProfileByIdResolver? _sshProfileById;
  final String Function()? _sshDefaultWorkingDirectoryResolver;
  final bool Function()? _sshUseLoginShellResolver;
  final rt.RuntimeTarget Function()? _defaultTargetResolver;
  final int Function()? _terminalScrollbackLinesResolver;

  SshProfile? profileFor(rt.RuntimeTarget target) => _profileFor(target);

  String executableFor(CliTool cli) => _resolveExecutableFor(cli);

  SshProfile? profileById(String id) => _sshProfileById?.call(id);

  TerminalTransportFactory? get transportFactory => _transportFactory;

  SshClientFactory? get sshClientFactory => _transportFactory?.sshClientFactory;

  rt.RuntimeTarget get _target =>
      _defaultTargetResolver?.call() ?? rt.RuntimeTarget.local();

  bool _useSshFor(rt.RuntimeTarget target) =>
      target.kind == RuntimeKind.ssh && _transportFactory != null;

  rt.RuntimeTarget _effectiveTarget(rt.RuntimeTarget? workTarget) =>
      workTarget ?? _target;

  SshProfile? _profileFor(rt.RuntimeTarget target) {
    final id = target.sshProfileId ?? sshProfileIdOfId(target.id);
    if (id != null && id.isNotEmpty) {
      return _sshProfileById?.call(id) ?? _sshProfileResolver?.call();
    }
    return _sshProfileResolver?.call();
  }

  int get _scrollbackLines => _terminalScrollbackLinesResolver?.call() ?? 10000;

  String _resolveExecutableFor(CliTool cli) =>
      _cliExecutableResolver?.call(cli) ?? _executableResolver();

  CliTool cliForMember(TeamProfile team, String memberId) {
    for (final m in team.members) {
      if (m.id == memberId) return m.cliWithin(team);
    }
    return team.cli;
  }

  TerminalSession newSession(CliTool cli, {rt.RuntimeTarget? workTarget}) {
    final executable = _resolveExecutableFor(cli);
    final scrollback = _scrollbackLines;
    final target = _effectiveTarget(workTarget);
    if (_useSshFor(target)) {
      final profile = _profileFor(target);
      if (profile == null) {
        return _terminalSessionFactory(
          executable: executable,
          scrollbackLines: scrollback,
        );
      }
      late final TerminalSession shell;
      shell = TerminalSession(
        executable: executable,
        scrollbackLines: scrollback,
        validateLaunch: false,
        usesRemoteTransport: true,
        parseExecutable: false,
        runtimeTarget: const RuntimeTarget.ssh(),
        transportStarter:
            (
              String executable, {
              required List<String> arguments,
              required String workingDirectory,
              required int columns,
              required int rows,
              Map<String, String>? environment,
            }) async {
              final memberSession = shell.sshMemberSession;
              if (memberSession == null) {
                throw StateError(
                  'SSH member session must be opened before connecting the shell',
                );
              }
              final remoteEnvironment = <String, String>{
                if (environment != null) ...environment,
              };
              final remoteWorkingDirectory = workingDirectory.isNotEmpty
                  ? workingDirectory
                  : (_sshDefaultWorkingDirectoryResolver?.call() ?? '');
              final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
                remoteExecutablePath: executable,
                arguments: arguments,
                workingDirectory: remoteWorkingDirectory.isEmpty
                    ? null
                    : remoteWorkingDirectory,
                environment: remoteEnvironment.isNotEmpty
                    ? remoteEnvironment
                    : null,
                useLoginShell: _sshUseLoginShellResolver?.call() ?? false,
              );
              return SshPtyTransport.start(
                memberSession: memberSession,
                command: SshPtyTransport.buildSessionCommand(command),
                columns: columns,
                rows: rows,
              );
            },
      );
      return shell;
    }
    return _terminalSessionFactory(
      executable: executable,
      scrollbackLines: scrollback,
    );
  }
}
