import 'package:flutter/scheduler.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../ssh/ssh_member_session.dart';
import '../termux/termux_connection_gate.dart';
import 'workspace_shell_connector.dart';
import 'workspace_terminal_registry.dart';

/// Connect/disconnect orchestration with generation guards (SSH stale-connect safe).
class WorkspaceTerminalConnectCoordinator {
  WorkspaceTerminalConnectCoordinator({
    required WorkspaceShellConnector connector,
    RuntimeTarget Function()? homeTarget,
    bool Function()? termuxConnected,
    String Function()? termuxWorkOpsBlockedMessage,
  }) : _connector = connector,
       _homeTarget = homeTarget ?? connector.homeTarget,
       _termuxConnected = termuxConnected,
       _termuxWorkOpsBlockedMessage = termuxWorkOpsBlockedMessage;

  final WorkspaceShellConnector _connector;
  final RuntimeTarget Function() _homeTarget;
  final bool Function()? _termuxConnected;
  final String Function()? _termuxWorkOpsBlockedMessage;

  /// Workspace / floating shell connect path with optional Termux gate.
  factory WorkspaceTerminalConnectCoordinator.termuxAware({
    required WorkspaceShellConnector connector,
    bool Function()? termuxConnected,
    String Function()? termuxWorkOpsBlockedMessage,
  }) => WorkspaceTerminalConnectCoordinator(
    connector: connector,
    homeTarget: connector.homeTarget,
    termuxConnected: termuxConnected,
    termuxWorkOpsBlockedMessage: termuxWorkOpsBlockedMessage,
  );

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
    final target = _connector.runtimeTargetFor(entry.spec);
    final cwd = entry.cwd.trim();
    if (!workspaceShellCanConnect(
      spec: entry.spec,
      cwd: cwd,
      home: _homeTarget(),
    )) {
      return;
    }
    if (entry.connected && entry.session.isRunning) return;
    final blockMessage = _termuxWorkOpsBlockedMessage?.call();
    final connected = _termuxConnected?.call();
    if (blockMessage != null && connected != null) {
      final blocked = termuxWorkOpsBlockMessage(
        target: target,
        home: _homeTarget(),
        termuxConnected: connected,
        message: blockMessage,
      );
      if (blocked != null) {
        entry.connected = false;
        entry.session.write('\r\n$blocked\r\n');
        onStateChanged();
        return;
      }
    }

    final generation = entry.bumpConnectGeneration();

    entry.session.applyTerminalTheme(theme);
    entry.connected = true;
    if (entry.controller.engine == null) {
      entry.controller.attach(entry.session.engine);
    }

    await _connector.disposeRemotePlane(entry.session);
    if (!stillLive(group, entry, generation) || !mounted()) return;

    SshMemberSession? sshSession;
    final targetKind = target.kind;
    if (targetKind == RuntimeKind.ssh || targetKind == RuntimeKind.termux) {
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
