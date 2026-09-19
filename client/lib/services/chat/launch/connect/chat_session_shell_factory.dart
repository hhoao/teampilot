import '../../../../models/runtime_target.dart' as rt;
import '../../../../models/runtime_target.dart'
    show RuntimeKind, sshProfileIdOfId, usesSshTransport;
import '../../../../models/ssh_profile.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/team_config.dart';
import '../../../cli/preset_resolver.dart';
import '../../../host/remote_command_codec.dart';
import '../../../cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../../cli/registry/cli_tool_registry.dart';
import '../../../ssh/ssh_client_factory.dart';
import '../../runtime/pty/ssh_pty_transport.dart';
import '../../../terminal/terminal_session.dart';
import '../../../terminal/terminal_transport_factory.dart';
import '../../../io/local_filesystem.dart';
import '../../../storage/home_storage.dart';
import '../../../workspace_dnd/runtime_target.dart';
import '../../../../cubits/chat_state.dart';

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
    HomeStorage? storage,
  }) : _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _terminalSessionFactory = terminalSessionFactory,
       _transportFactory = transportFactory,
       _sshProfileResolver = sshProfileResolver,
       _sshProfileById = sshProfileById,
       _sshDefaultWorkingDirectoryResolver = sshDefaultWorkingDirectoryResolver,
       _sshUseLoginShellResolver = sshUseLoginShellResolver,
       _defaultTargetResolver = defaultTargetResolver,
       _terminalScrollbackLinesResolver = terminalScrollbackLinesResolver,
       _storage = storage;

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
  final HomeStorage? _storage;

  SshProfile? profileFor(rt.RuntimeTarget target) => _profileFor(target);

  String executableFor(CliTool cli) => _resolveExecutableFor(cli);

  SshProfile? profileById(String id) => _sshProfileById?.call(id);

  TerminalTransportFactory? get transportFactory => _transportFactory;

  SshClientFactory? get sshClientFactory => _transportFactory?.sshClientFactory;

  rt.RuntimeTarget get _target =>
      _defaultTargetResolver?.call() ?? rt.RuntimeTarget.local();

  bool _useSshFor(rt.RuntimeTarget target) =>
      usesSshTransport(target.kind) && _transportFactory != null;

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

  CliTool cliForMember(
    TeamProfile team,
    String memberId, {
    List<CliPreset> globalPresets = const [],
  }) {
    for (final m in team.members) {
      if (m.id == memberId) {
        return memberLaunchCli(
          team: team,
          member: m,
          globalPresets: globalPresets,
        );
      }
    }
    return team.cli;
  }

  TerminalSession newSession(CliTool cli, {rt.RuntimeTarget? workTarget}) {
    final executable = _resolveExecutableFor(cli);
    final scrollback = _scrollbackLines;
    final target = _effectiveTarget(workTarget);
    final startupDeadline = _startupDeadlineFor(cli);
    if (_useSshFor(target)) {
      final profile = _profileFor(target);
      if (profile == null) {
        return _localSession(
          executable: executable,
          scrollback: scrollback,
          startupDeadline: startupDeadline,
        );
      }
      late final TerminalSession shell;
      shell = TerminalSession(
        executable: executable,
        fs: _storage?.fs ?? LocalFilesystem(),
        scrollbackLines: scrollback,
        validateLaunch: false,
        usesRemoteTransport: true,
        parseExecutable: false,
        startupDeadline: startupDeadline,
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
              final command = buildMemberRemoteCommand(
                profile: memberSession.profile,
                executable: executable,
                arguments: arguments,
                remoteWorkingDirectory: remoteWorkingDirectory,
                environment: remoteEnvironment,
                useLoginShell: _sshUseLoginShellResolver?.call() ?? false,
              );
              return SshPtyTransport.start(
                memberSession: memberSession,
                command: command,
                columns: columns,
                rows: rows,
              );
            },
      );
      return shell;
    }
    return _localSession(
      executable: executable,
      scrollback: scrollback,
      startupDeadline: startupDeadline,
    );
  }

  /// Remote command for a CLI member shell: the `tp1:` structured-exec
  /// payload for embedded targets, the legacy POSIX login-shell string
  /// otherwise (byte-for-byte the pre-codec output).
  static String buildMemberRemoteCommand({
    required SshProfile profile,
    required String executable,
    required List<String> arguments,
    required String remoteWorkingDirectory,
    required Map<String, String>? environment,
    required bool useLoginShell,
  }) {
    final spec = RemoteCommandSpec(
      argv: [executable, ...arguments],
      cwd: remoteWorkingDirectory.isEmpty ? null : remoteWorkingDirectory,
      env: (environment != null && environment.isNotEmpty) ? environment : null,
    );
    final codec = const RemoteCommandCodec();
    return profile.embeddedTarget
        ? codec.encodeEmbedded(spec)
        : codec.encodeLegacy(spec, useLoginShell: useLoginShell);
  }

  Duration _startupDeadlineFor(CliTool cli) {
    return CliToolRegistry.builtIn()
            .capability<TerminalBehaviorCapability>(cli)
            ?.startupDeadline ??
        const Duration(seconds: 15);
  }

  TerminalSession _localSession({
    required String executable,
    required int scrollback,
    required Duration startupDeadline,
  }) {
    final session = _terminalSessionFactory(
      executable: executable,
      scrollbackLines: scrollback,
    );
    if (session.startupDeadline == startupDeadline) return session;
    // Default factory sessions are rebuilt so CLI-specific deadlines apply
    // (e.g. Cursor 45s). Subclasses from test/custom factories keep identity
    // — replacing them would drop overrides such as [TerminalSession.isRunning].
    if (session.runtimeType != TerminalSession) return session;
    return TerminalSession(
      executable: executable,
      fs: _storage?.fs ?? LocalFilesystem(),
      scrollbackLines: scrollback,
      startupDeadline: startupDeadline,
      validateLaunch: session.validateLaunch,
      usesRemoteTransport: session.usesRemoteTransport,
      parseExecutable: session.parseExecutable,
    );
  }
}
