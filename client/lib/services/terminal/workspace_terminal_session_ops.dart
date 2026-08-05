import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/workspace_terminal_session_spec.dart';
import 'workspace_shell_connector.dart';
import 'workspace_terminal_connect_coordinator.dart';
import 'workspace_terminal_registry.dart';

/// Shared create+connect path for workspace terminal tabs (panel + Run inject).
class WorkspaceTerminalSessionOps {
  /// Creates a session and adds a group entry without connecting the transport.
  ///
  /// Use when the UI tab should appear before [connectEntry] (floating open).
  Future<WorkspaceTerminalEntry> createEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required bool select,
    String titleLabel = '',
    bool followWorkspace = false,
  }) async {
    final session = connector.createSession(spec);
    final label = titleLabel.isNotEmpty
        ? titleLabel
        : await connector.labelForSpec(spec);
    return group.addEntry(
      cwd: cwd,
      spec: spec,
      session: session,
      select: select,
      titleLabel: label,
      followWorkspace: followWorkspace,
    );
  }

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
    final entry = await createEntry(
      group: group,
      connector: connector,
      cwd: cwd,
      spec: spec,
      select: select,
      titleLabel: titleLabel,
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
