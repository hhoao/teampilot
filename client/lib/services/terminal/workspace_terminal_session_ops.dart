import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/workspace_terminal_session_spec.dart';
import 'workspace_shell_connector.dart';
import 'workspace_terminal_connect_coordinator.dart';
import 'workspace_terminal_registry.dart';

/// Shared create+connect path for workspace terminal tabs (panel + Run inject).
class WorkspaceTerminalSessionOps {
  /// Creates a session, adds a group entry, and connects the transport.
  Future<WorkspaceTerminalEntry> openEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    required bool select,
    String titleLabel = '',
    bool followWorkspace = false,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {
    final session = connector.createSession(spec);
    final label = titleLabel.isNotEmpty
        ? titleLabel
        : await connector.labelForSpec(spec);
    final entry = group.addEntry(
      cwd: cwd,
      spec: spec,
      session: session,
      select: select,
      titleLabel: label,
      followWorkspace: followWorkspace,
    );
    await connectEntry(
      group: group,
      entry: entry,
      connectCoordinator: connectCoordinator,
      theme: theme,
      sshConnectFailedMessage: sshConnectFailedMessage,
      onStateChanged: onStateChanged,
      mounted: mounted,
    );
    return entry;
  }

  /// Connects an existing entry (select / cwd sync / SSH reconnect).
  Future<void> connectEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceTerminalEntry entry,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) {
    return connectCoordinator.connect(
      group: group,
      entry: entry,
      theme: theme,
      sshConnectFailedMessage: sshConnectFailedMessage,
      onStateChanged: onStateChanged ?? () {},
      mounted: mounted ?? () => true,
    );
  }
}
