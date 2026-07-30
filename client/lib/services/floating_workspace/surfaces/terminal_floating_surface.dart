import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../pages/workbench/shell_terminal_surface.dart';
import '../../../services/workbench/workbench_shell_actions.dart';
import '../../../services/workbench/workbench_shell_launcher.dart';
import '../../commands/command_ids.dart';
import '../../terminal/workspace_terminal_registry.dart';
import '../../terminal/workspace_terminal_run_service.dart';
import '../floating_surface.dart';

/// Floating surface that hosts a workspace shell terminal for one entry id.
///
/// Domain open is driven by [WorkbenchShellLauncher]; [activate] selects the
/// registry entry so the shared panel shows the right PTY.
class TerminalFloatingSurface extends FloatingSurface {
  TerminalFloatingSurface({
    required FloatingWorkspaceCubit floating,
    required WorkspaceTerminalRegistry registry,
    required WorkspaceTerminalRunService runService,
  }) : _floating = floating,
       _registry = registry,
       _runService = runService;

  final FloatingWorkspaceCubit _floating;
  final WorkspaceTerminalRegistry _registry;
  final WorkspaceTerminalRunService _runService;

  @override
  String get id => 'terminal';

  @override
  FloatingEmptyAction? get emptyAction => const FloatingEmptyAction(
    commandId: CommandIds.floatingNewTerminal,
    labelKey: 'newTerminal',
    icon: Icons.terminal_outlined,
  );

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final entryId = payload is String ? payload.trim() : '';
    final label = entryId.isEmpty
        ? ''
        : (_registry.groupFor(workspaceId).entryById(entryId)?.titleLabel ??
              '');
    final title = label.trim().isNotEmpty
        ? label
        : (entryId.isEmpty ? 'Terminal' : entryId);
    return FloatingTab(
      id: entryId.isEmpty ? 'shell:' : floatingShellTabId(entryId),
      surfaceId: id,
      title: title,
      payload: entryId.isEmpty ? null : entryId,
    );
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final entryId = tab.payload;
    if (entryId is! String || entryId.isEmpty) {
      return const SizedBox.shrink();
    }
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final group = _registry.groupFor(workspaceId);
    final entry = group.entryById(entryId);
    final cwd = entry?.cwd.trim().isNotEmpty == true
        ? entry!.cwd
        : (context.read<ChatCubit>().state.workspaces
                  .where((w) => w.workspaceId == workspaceId)
                  .firstOrNull
                  ?.firstFolderPath
                  .trim() ??
              '');
    if (cwd.isEmpty) {
      return const SizedBox.shrink();
    }
    return ShellTerminalSurface(
      workspaceId: workspaceId,
      tabScopeId: workspaceId,
      workingDirectory: cwd,
      activeEntryId: entryId,
    );
  }

  @override
  Future<void> activate(FloatingTab tab) async {
    final entryId = tab.payload;
    if (entryId is! String || entryId.isEmpty) return;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;
    final group = _registry.groupFor(workspaceId);
    if (group.entryById(entryId) == null) return;
    group.activeId = entryId;
  }

  @override
  Future<bool> canClose(FloatingTab tab) async => true;

  @override
  void onTabClosed(FloatingTab tab) {
    final entryId = tab.payload;
    if (entryId is! String || entryId.isEmpty) return;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;
    disposeWorkbenchShellDomain(
      runService: _runService,
      group: _registry.groupFor(workspaceId),
      entryId: entryId,
    );
  }
}
