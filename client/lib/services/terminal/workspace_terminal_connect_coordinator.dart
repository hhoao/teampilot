import 'package:flutter/scheduler.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/runtime_target.dart';
import '../ssh/ssh_member_session.dart';
import 'workspace_shell_connector.dart';
import 'workspace_terminal_registry.dart';

/// Connect/disconnect orchestration with generation guards (SSH stale-connect safe).
class WorkspaceTerminalConnectCoordinator {
  WorkspaceTerminalConnectCoordinator({required WorkspaceShellConnector connector})
    : _connector = connector;

  final WorkspaceShellConnector _connector;

  static bool stillLive(
    WorkspaceTerminalGroup group,
    WorkspaceTerminalEntry entry,
    int generation,
  ) =>
      generation == entry.connectGeneration &&
      group.entries.any((e) => e.id == entry.id) &&
      !entry.session.isDisposed;

  Future<void> connect({
    required WorkspaceTerminalGroup group,
    required WorkspaceTerminalEntry entry,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    required VoidCallback onStateChanged,
    required bool Function() mounted,
  }) async {
    final cwd = entry.cwd.trim();
    if (cwd.isEmpty) return;
    if (entry.connected && entry.session.isRunning) return;

    final generation = entry.bumpConnectGeneration();

    entry.session.applyTerminalTheme(theme);
    entry.connected = true;
    if (entry.controller.engine == null) {
      entry.controller.attach(entry.session.engine);
    }

    await _connector.disposeRemotePlane(entry.session);
    if (!stillLive(group, entry, generation) || !mounted()) return;

    SshMemberSession? sshSession;
    if (_connector.runtimeTargetFor(entry.spec).kind == RuntimeKind.ssh) {
      sshSession = await _connector.openSshSession(entry.spec);
      if (!stillLive(group, entry, generation) || !mounted()) {
        sshSession?.close();
        return;
      }
      if (sshSession == null) {
        entry.connected = false;
        entry.session.write('\r\n$sshConnectFailedMessage\r\n');
        onStateChanged();
        return;
      }
    }

    entry.session.sshMemberSession = sshSession;
    final plan = _connector.resolveLaunchPlan(
      spec: entry.spec,
      workingDirectory: cwd,
    );

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted() || !stillLive(group, entry, generation)) return;
      if (entry.session.isRunning || entry.session.isConnecting) return;
      entry.session.connectWorkspaceShell(
        plan: plan,
        onProcessStarted: onStateChanged,
        onProcessFailed: (_) => onStateChanged(),
        onProcessExited: () {
          entry.connected = false;
          onStateChanged();
        },
      );
    });
  }
}
