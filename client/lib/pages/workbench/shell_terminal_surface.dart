import 'package:flutter/material.dart';

import '../../widgets/workspace_terminal_panel.dart';

/// Workspace shell terminal body (floating-capable; no dock chrome).
///
/// Hosts a single [WorkspaceTerminalPanel] that multi-entry IndexedStacks
/// internally so [WorkspaceTerminalHoldHandle] stays bound to one panel state.
class ShellTerminalSurface extends StatelessWidget {
  const ShellTerminalSurface({
    required this.workspaceId,
    required this.tabScopeId,
    required this.workingDirectory,
    this.holdHandle,
    this.activeEntryId,
    super.key,
  });

  final String workspaceId;
  final String tabScopeId;
  final String workingDirectory;
  final WorkspaceTerminalHoldHandle? holdHandle;
  final String? activeEntryId;

  @override
  Widget build(BuildContext context) {
    return WorkspaceTerminalPanel(
      // Registry / connect key matches the dock: tabScopeId, not workspaceId.
      key: ValueKey('shell-terminal-$workspaceId-$tabScopeId'),
      workspaceId: tabScopeId,
      workingDirectory: workingDirectory,
      holdHandle: holdHandle,
      showChrome: false,
      activeEntryId: activeEntryId,
    );
  }
}
