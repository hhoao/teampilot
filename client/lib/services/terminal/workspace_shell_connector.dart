import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/runtime_target.dart';
import '../../models/workspace_shell_launch_plan.dart';
import '../../models/ssh_profile.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../session/launch_command_builder.dart';
import '../session/remote_flashskyai_command_builder.dart';
import '../ssh/ssh_member_session.dart';
import '../workspace_dnd/runtime_target.dart' as dnd;
import 'ssh_pty_transport.dart';
import 'terminal_session.dart';
import 'terminal_transport_factory.dart';
import 'workspace_interactive_shell.dart';

/// Materializes workspace-terminal [TerminalSession]s and opens their transports.
class WorkspaceShellConnector {
  WorkspaceShellConnector({
    required TerminalTransportFactory transportFactory,
    required SshProfileRepository sshProfileRepository,
    bool Function()? sshUseLoginShell,
  }) : _transportFactory = transportFactory,
       _sshProfileRepository = sshProfileRepository,
       _sshUseLoginShell = sshUseLoginShell ?? (() => true);

  final TerminalTransportFactory _transportFactory;
  final SshProfileRepository _sshProfileRepository;
  final bool Function() _sshUseLoginShell;

  static const _remoteShell = r'${SHELL:-/bin/bash}';

  RuntimeTarget runtimeTargetFor(WorkspaceTerminalSessionSpec spec) =>
      switch (spec) {
        WorkspaceTerminalLocalSpec() => RuntimeTarget.local(),
        WorkspaceTerminalWorkspaceTargetSpec(:final targetId) =>
          _runtimeTargetFromId(targetId),
        WorkspaceTerminalSshProfileSpec(:final profileId) =>
          RuntimeTarget.ssh(profileId, label: ''),
      };

  TerminalSession createSession(WorkspaceTerminalSessionSpec spec) {
    final target = runtimeTargetFor(spec);
    if (target.kind == RuntimeKind.ssh) {
      return _createSshSession();
    }
    return TerminalSession(
      executable: _posixShellPathFor(spec),
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
      RuntimeKind.wsl => _wslLaunchPlan(
        distro: target.wslDistro ?? '',
        shellPath: _posixShellPathFor(spec),
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
    return SshMemberSession.open(
      _transportFactory.sshClientFactory,
      profile,
    );
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
    final id = switch (spec) {
      WorkspaceTerminalSshProfileSpec(:final profileId) => profileId,
      WorkspaceTerminalWorkspaceTargetSpec(:final targetId) =>
        sshProfileIdOfId(targetId) ?? '',
      _ => '',
    };
    if (id.isEmpty) return null;
    return _sshProfileRepository.findById(id);
  }

  TerminalSession _createSshSession() {
    late final TerminalSession shell;
    shell = TerminalSession(
      executable: _remoteShell,
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
            final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
              remoteExecutablePath: executable,
              arguments: arguments,
              workingDirectory: workingDirectory.isEmpty
                  ? null
                  : workingDirectory,
              environment: environment,
              useLoginShell: _sshUseLoginShell(),
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

  String _posixShellPathFor(WorkspaceTerminalSessionSpec spec) =>
      switch (spec) {
        WorkspaceTerminalLocalSpec(:final shellPath) => shellPath,
        _ => WorkspaceInteractiveShell.executable(),
      };

  WorkspaceShellLaunchPlan _localLaunchPlan({
    required WorkspaceTerminalSessionSpec spec,
    required String workingDirectory,
    required RuntimeTarget runtimeTarget,
  }) {
    final shellPath = _posixShellPathFor(spec);
    final cwd = LaunchCommandBuilder.workingDirectoryForProcess(
      _nonEmptyCwd(workingDirectory),
      useWslPaths: false,
    );
    return WorkspaceShellLaunchPlan(
      executable: shellPath,
      arguments: WorkspaceInteractiveShell.launchArguments(shellPath),
      workingDirectory: cwd,
      useWslPaths: false,
      inheritHostEnvironment: true,
      runtimeTarget: runtimeTarget,
      usesRemoteTransport: false,
    );
  }

  WorkspaceShellLaunchPlan _wslLaunchPlan({
    required String distro,
    required String shellPath,
    required String workingDirectory,
    required RuntimeTarget runtimeTarget,
  }) {
    final cwd = workingDirectory.trim();
    final wslArgs = <String>[];
    final trimmedDistro = distro.trim();
    if (trimmedDistro.isNotEmpty) wslArgs.addAll(['-d', trimmedDistro]);
    if (cwd.isNotEmpty) wslArgs.addAll(['--cd', cwd]);
    wslArgs.add(p.basename(shellPath));
    wslArgs.addAll(WorkspaceInteractiveShell.launchArguments(shellPath));

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
      arguments: WorkspaceInteractiveShell.launchArguments('/bin/bash'),
      workingDirectory: workingDirectory.trim(),
      useWslPaths: false,
      inheritHostEnvironment: false,
      runtimeTarget: RuntimeTarget.ssh('', label: ''),
      usesRemoteTransport: true,
    );
  }

  RuntimeTarget _runtimeTargetFromId(String id) => switch (runtimeKindOfId(id)) {
    RuntimeKind.ssh => RuntimeTarget.ssh(
      sshProfileIdOfId(id) ?? '',
      label: '',
    ),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };

  dnd.RuntimeTarget _dndTargetFor(RuntimeTarget target) => switch (target.kind) {
    RuntimeKind.ssh => const dnd.RuntimeTarget.ssh(),
    RuntimeKind.wsl => dnd.RuntimeTarget.wsl(),
    RuntimeKind.local => Platform.isWindows
        ? dnd.RuntimeTarget.localWindows()
        : dnd.RuntimeTarget.localPosix(),
  };

  String _nonEmptyCwd(String cwd) =>
      cwd.trim().isNotEmpty ? cwd.trim() : Directory.current.path;
}
