import 'dart:io';

import 'package:tp_sshd/tp_sshd.dart' show SSHPtyDimensions;

import '../../models/runtime_target.dart';
import '../../models/workspace_shell_launch_plan.dart';
import '../../models/ssh_profile.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../storage/work_target_canonicalizer.dart';
import '../chat/launch/connect/launch_command_builder.dart';
import '../host/remote_command_codec.dart';
import '../ssh/ssh_member_session.dart';
import '../workspace_dnd/runtime_target.dart' as dnd;
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../chat/runtime/pty/ssh_pty_transport.dart';
import 'terminal_session.dart';
import 'terminal_transport_factory.dart';
import '../host/host_interactive_shell.dart';
import '../host/host_interactive_shell_kind.dart';

/// Materializes workspace-terminal [TerminalSession]s and opens their transports.
class WorkspaceShellConnector {
  WorkspaceShellConnector({
    required TerminalTransportFactory transportFactory,
    required SshProfileRepository sshProfileRepository,
    bool Function()? sshUseLoginShell,
    RuntimeTarget Function()? homeTarget,
    SshProfile? Function(String profileId)? profileById,
    Filesystem? fs,
  }) : _transportFactory = transportFactory,
       _sshProfileRepository = sshProfileRepository,
       _sshUseLoginShell = sshUseLoginShell ?? (() => true),
       _homeTarget = homeTarget ?? RuntimeTarget.local,
       _profileById = profileById,
       _fs = fs ?? LocalFilesystem();

  final TerminalTransportFactory _transportFactory;
  final SshProfileRepository _sshProfileRepository;
  final bool Function() _sshUseLoginShell;
  final RuntimeTarget Function() _homeTarget;
  final SshProfile? Function(String profileId)? _profileById;
  final Filesystem _fs;

  RuntimeTarget Function() get homeTarget => _homeTarget;

  static final _remoteShell = HostInteractiveShell.remotePosixExecutable;

  RuntimeTarget runtimeTargetFor(WorkspaceTerminalSessionSpec spec) =>
      switch (spec) {
        WorkspaceTerminalLocalSpec() => RuntimeTarget.local(),
        WorkspaceTerminalWorkspaceTargetSpec(:final targetId) =>
          WorkTargetCanonicalizer.resolve(targetId, home: _homeTarget()),
        WorkspaceTerminalSshProfileSpec(:final profileId) => RuntimeTarget.ssh(
          profileId,
          label: '',
        ),
      };

  TerminalSession createSession(WorkspaceTerminalSessionSpec spec) {
    final target = runtimeTargetFor(spec);
    if (target.kind == RuntimeKind.ssh || target.kind == RuntimeKind.termux) {
      return _createSshSession();
    }
    return TerminalSession(
      executable: _posixShellSpec(spec).executable,
      fs: _fs,
      validateLaunch: false,
      parseExecutable: false,
      runtimeTarget: _dndTargetFor(target),
    );
  }

  WorkspaceShellLaunchPlan resolveLaunchPlan({
    required WorkspaceTerminalSessionSpec spec,
    required String workingDirectory,
  }) {
    final target = runtimeTargetFor(spec);
    return switch (target.kind) {
      RuntimeKind.ssh => _sshLaunchPlan(workingDirectory: workingDirectory),
      RuntimeKind.termux => _sshLaunchPlan(workingDirectory: workingDirectory),
      RuntimeKind.wsl => _wslLaunchPlan(
        distro: target.wslDistro ?? '',
        shell: _posixShellSpec(spec),
        workingDirectory: workingDirectory,
        runtimeTarget: target,
      ),
      RuntimeKind.local => _localLaunchPlan(
        spec: spec,
        workingDirectory: workingDirectory,
        runtimeTarget: target,
      ),
    };
  }

  Future<SshMemberSession?> openSshSession(
    WorkspaceTerminalSessionSpec spec,
  ) async {
    final profile = await _profileFor(spec);
    if (profile == null) return null;
    return SshMemberSession.open(_transportFactory.sshClientFactory, profile);
  }

  Future<void> disposeRemotePlane(TerminalSession session) async {
    session.sshMemberSession?.close();
    session.sshMemberSession = null;
  }

  Future<String> labelForSpec(WorkspaceTerminalSessionSpec spec) async {
    switch (spec) {
      case WorkspaceTerminalLocalSpec():
        return 'Local';
      case WorkspaceTerminalWorkspaceTargetSpec(:final targetId):
        final profileId = sshProfileIdOfId(targetId);
        if (profileId != null) {
          final profile = await _sshProfileRepository.findById(profileId);
          if (profile != null) return profile.hostIdentifier;
        }
        final distro = wslDistroOfId(targetId);
        if (distro != null && distro.isNotEmpty) return 'WSL · $distro';
        if (targetId == WorkspaceFolder.localTargetId) return 'Local';
        return targetId;
      case WorkspaceTerminalSshProfileSpec(:final profileId):
        final profile = await _sshProfileRepository.findById(profileId);
        if (profile == null) return 'SSH';
        return profile.hostIdentifier;
    }
  }

  Future<SshProfile?> _profileFor(WorkspaceTerminalSessionSpec spec) async {
    final target = runtimeTargetFor(spec);
    if (target.kind == RuntimeKind.termux) {
      return _profileById?.call('termux') ??
          await _sshProfileRepository.findById('termux');
    }
    final id = switch (spec) {
      WorkspaceTerminalSshProfileSpec(:final profileId) => profileId,
      WorkspaceTerminalWorkspaceTargetSpec(:final targetId) =>
        sshProfileIdOfId(targetId) ?? '',
      _ => '',
    };
    if (id.isEmpty) return null;
    return _sshProfileRepository.findById(id);
  }

  /// Remote command for the SSH workspace shell. Embedded targets get `null`
  /// — a bare `shell` request, so the embedded server picks the OS-native
  /// shell — while legacy targets keep the POSIX login-shell string
  /// (byte-for-byte the pre-codec output). The embedded shell's working
  /// directory rides [buildShellEnvironment] instead.
  static String? buildShellRemoteCommand({
    required SshProfile profile,
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String>? environment,
    required bool useLoginShell,
  }) {
    if (profile.embeddedTarget) return null;
    return const RemoteCommandCodec().encodeLegacy(
      RemoteCommandSpec(
        argv: [executable, ...arguments],
        cwd: workingDirectory.isEmpty ? null : workingDirectory,
        env: environment,
      ),
      useLoginShell: useLoginShell,
    );
  }

  /// Environment sent with the embedded workspace shell's bare `shell`
  /// request. The SSH `shell` request has no working-directory field, so the
  /// embedded target's requested directory rides the pty environment under
  /// [SSHPtyDimensions.workingDirectoryEnv] — the embedded server spawns the
  /// shell there and consumes the variable. Legacy targets get `null`: their
  /// working directory is part of the command string.
  static Map<String, String>? buildShellEnvironment({
    required SshProfile profile,
    required String workingDirectory,
  }) {
    if (!profile.embeddedTarget) return null;
    final cwd = workingDirectory.trim();
    if (cwd.isEmpty) return null;
    return {SSHPtyDimensions.workingDirectoryEnv: cwd};
  }

  TerminalSession _createSshSession() {
    late final TerminalSession shell;
    shell = TerminalSession(
      executable: _remoteShell,
      fs: _fs,
      validateLaunch: false,
      usesRemoteTransport: true,
      parseExecutable: false,
      runtimeTarget: const dnd.RuntimeTarget.ssh(),
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
                'SSH workspace shell requires an open member session',
              );
            }
            final command = buildShellRemoteCommand(
              profile: memberSession.profile,
              executable: executable,
              arguments: arguments,
              workingDirectory: workingDirectory,
              environment: environment,
              useLoginShell: _sshUseLoginShell(),
            );
            return SshPtyTransport.start(
              memberSession: memberSession,
              // null → bare `shell` request; the server picks the shell. The
              // requested working directory rides the pty environment.
              command: command,
              columns: columns,
              rows: rows,
              environment: buildShellEnvironment(
                profile: memberSession.profile,
                workingDirectory: workingDirectory,
              ),
            );
          },
    );
    return shell;
  }

  HostInteractiveShellSpec _posixShellSpec(WorkspaceTerminalSessionSpec spec) =>
      switch (spec) {
        WorkspaceTerminalLocalSpec(:final shellPath) =>
          HostInteractiveShell.resolveSpec(shellPath),
        _ => HostInteractiveShell.defaultSpec(),
      };

  WorkspaceShellLaunchPlan _localLaunchPlan({
    required WorkspaceTerminalSessionSpec spec,
    required String workingDirectory,
    required RuntimeTarget runtimeTarget,
  }) {
    final shell = _posixShellSpec(spec);
    final cwd = LaunchCommandBuilder.workingDirectoryForProcess(
      _nonEmptyCwd(workingDirectory),
      useWslPaths: false,
    );
    return WorkspaceShellLaunchPlan(
      executable: shell.executable,
      arguments: shell.launchArguments,
      workingDirectory: cwd,
      useWslPaths: false,
      inheritHostEnvironment: true,
      runtimeTarget: runtimeTarget,
      usesRemoteTransport: false,
    );
  }

  WorkspaceShellLaunchPlan _wslLaunchPlan({
    required String distro,
    required HostInteractiveShellSpec shell,
    required String workingDirectory,
    required RuntimeTarget runtimeTarget,
  }) {
    final cwd = workingDirectory.trim();
    final wslArgs = <String>[];
    final trimmedDistro = distro.trim();
    if (trimmedDistro.isNotEmpty) wslArgs.addAll(['-d', trimmedDistro]);
    if (cwd.isNotEmpty) wslArgs.addAll(['--cd', cwd]);
    wslArgs.addAll(HostInteractiveShell.wslArgumentsFor(shell));

    return WorkspaceShellLaunchPlan(
      executable: 'wsl.exe',
      arguments: wslArgs,
      workingDirectory: LaunchCommandBuilder.workingDirectoryForProcess(
        cwd,
        useWslPaths: true,
      ),
      useWslPaths: true,
      inheritHostEnvironment: true,
      runtimeTarget: runtimeTarget,
      usesRemoteTransport: false,
    );
  }

  WorkspaceShellLaunchPlan _sshLaunchPlan({required String workingDirectory}) {
    return WorkspaceShellLaunchPlan(
      executable: _remoteShell,
      arguments: HostInteractiveShell.launchArgumentsFor(
        HostInteractiveShellKind.bash,
      ),
      workingDirectory: workingDirectory.trim(),
      useWslPaths: false,
      inheritHostEnvironment: false,
      runtimeTarget: RuntimeTarget.ssh('', label: ''),
      usesRemoteTransport: true,
    );
  }

  dnd.RuntimeTarget _dndTargetFor(RuntimeTarget target) =>
      switch (target.kind) {
        RuntimeKind.ssh => const dnd.RuntimeTarget.ssh(),
        RuntimeKind.termux => const dnd.RuntimeTarget.ssh(),
        RuntimeKind.wsl => dnd.RuntimeTarget.wsl(),
        RuntimeKind.local =>
          Platform.isWindows
              ? dnd.RuntimeTarget.localWindows()
              : dnd.RuntimeTarget.localPosix(),
      };

  String _nonEmptyCwd(String cwd) =>
      cwd.trim().isNotEmpty ? cwd.trim() : Directory.current.path;
}
