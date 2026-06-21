import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../widgets/resizable_split_view.dart';
import '../../widgets/workspace_terminal_panel.dart';

/// Center column of the workspace shell: the workbench [child] with the optional
/// bottom workspace terminal beneath it. The right tools panel is NOT laid out
/// here — it is a project-page-level sibling (see `RightToolsHost`), so toggling
/// it never restructures this subtree.
class WorkspaceShellMainWithTerminal extends StatelessWidget {
  const WorkspaceShellMainWithTerminal({
    super.key,
    required this.preferences,
    required this.child,
    this.workspaceTerminalWorkingDirectory,
    this.workspaceWorkspaceId,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final String? workspaceTerminalWorkingDirectory;
  final String? workspaceWorkspaceId;

  @override
  Widget build(BuildContext context) {
    return WorkspaceShellCenterColumnWithTerminal(
      workspaceTerminalWorkingDirectory: workspaceTerminalWorkingDirectory,
      workspaceWorkspaceId: workspaceWorkspaceId,
      child: child,
    );
  }
}

/// Bottom terminal under the center workbench only (not under right tools).
class WorkspaceShellCenterColumnWithTerminal extends StatelessWidget {
  const WorkspaceShellCenterColumnWithTerminal({
    super.key,
    required this.child,
    this.workspaceTerminalWorkingDirectory,
    this.workspaceWorkspaceId,
  });

  final Widget child;
  final String? workspaceTerminalWorkingDirectory;
  final String? workspaceWorkspaceId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LayoutCubit, LayoutState>(
      buildWhen: (previous, next) =>
          previous.preferences.workspaceTerminalVisible !=
              next.preferences.workspaceTerminalVisible ||
          previous.preferences.workspaceTerminalHeight !=
              next.preferences.workspaceTerminalHeight,
      builder: (context, layoutState) {
        final prefs = layoutState.preferences;
        if (!prefs.workspaceTerminalVisible) {
          return child;
        }
        final scoped = workspaceTerminalWorkingDirectory?.trim() ?? '';
        final cwd = scoped.isNotEmpty
            ? scoped
            : context.watch<ChatCubit>().activeTabWorkingDirectory;
        final terminalHeight = prefs.workspaceTerminalHeight.clamp(
          LayoutPreferences.minWorkspaceTerminalHeight,
          LayoutPreferences.maxWorkspaceTerminalHeight,
        );
        final workspaceId = workspaceWorkspaceId?.trim() ?? '';
        // Key by the registry-group identity only — NOT cwd. Keeping cwd out of
        // the key means a same-workspace cwd change keeps the same panel State, so
        // the cwd update flows through didUpdateWidget -> _syncActiveEntryCwd
        // (which updates the active entry + reconnects). Including cwd here would
        // recreate the State, whose bootstrap re-attaches existing terminals
        // without updating their cwd, stranding them at the old path.
        final terminalGroupId = workspaceId.isNotEmpty ? workspaceId : cwd;
        return ResizableSplitView(
          axis: Axis.vertical,
          primaryAtEnd: true,
          first: child,
          second: WorkspaceTerminalPanel(
            key: ValueKey('workspace-terminal-$terminalGroupId'),
            workspaceId: terminalGroupId,
            workingDirectory: cwd,
          ),
          initialPrimarySize: terminalHeight,
          minPrimarySize: LayoutPreferences.minWorkspaceTerminalHeight,
          minSecondarySize: LayoutPreferences.minWorkbenchMainWidth,
          maxPrimarySize: LayoutPreferences.maxWorkspaceTerminalHeight,
          onPrimarySizeChanged: (height) {
            context.read<LayoutCubit>().setWorkspaceTerminalHeight(height);
          },
        );
      },
    );
  }
}
