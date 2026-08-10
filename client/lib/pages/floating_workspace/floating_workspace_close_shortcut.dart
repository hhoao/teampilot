import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../services/commands/key_chord.dart';
import '../../services/floating_workspace/close_floating_tab.dart';
import '../../services/floating_workspace/floating_surface_registry.dart';
import '../../widgets/workbench/workbench_shell_run_sync.dart';

/// Intent for Ctrl/Cmd+W scoped to the floating workspace panel.
class FloatingWorkspaceCloseTabIntent extends Intent {
  const FloatingWorkspaceCloseTabIntent();
}

/// Panel-local Shortcuts/Actions: empty → minimize; active tab → close pipeline.
///
/// Task 9 wraps [FloatingWorkspacePanel] with this so session-strip shortcuts
/// are not fought globally.
class FloatingWorkspaceCloseShortcut extends StatelessWidget {
  const FloatingWorkspaceCloseShortcut({
    required this.registry,
    required this.child,
    this.autofocus = false,
    super.key,
  });

  final FloatingSurfaceRegistry registry;
  final Widget child;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isMac = defaultIsMacOS();
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: isMac,
          control: !isMac,
        ): const FloatingWorkspaceCloseTabIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FloatingWorkspaceCloseTabIntent:
              CallbackAction<FloatingWorkspaceCloseTabIntent>(
                onInvoke: (intent) {
                  _handleClose(context);
                  return null;
                },
              ),
        },
        child: Focus(autofocus: autofocus, child: child),
      ),
    );
  }

  void _handleClose(BuildContext context) {
    final cubit = context.read<FloatingWorkspaceCubit>();
    final workbench = context.read<WorkbenchCubit>();
    final workspaceId = cubit.state.activeWorkspaceId.trim();
    if (workspaceId.isEmpty) return;

    final strip = workbench.state.bar(workspaceId).floating;
    if (strip.order.isEmpty) {
      cubit.minimize(closeIfEmpty: true);
      return;
    }
    final activeId = strip.activeId;
    if (activeId == null || !strip.contains(activeId)) {
      cubit.minimize(closeIfEmpty: true);
      return;
    }

    final surfaceId = switch (activeId.kind) {
      WorkbenchTabKind.shell => 'terminal',
      WorkbenchTabKind.run => 'run',
      WorkbenchTabKind.file => 'filePreview',
      WorkbenchTabKind.diff => 'diffPreview',
      WorkbenchTabKind.session => null,
    };
    if (surfaceId == null) {
      cubit.minimize(closeIfEmpty: true);
      return;
    }
    final surface = registry[surfaceId];
    final tab = surface == null
        ? null
        : resolveFloatingTabForId(
            registry: registry,
            workspaceId: workspaceId,
            id: activeId,
          );
    if (tab == null) {
      unawaited(workbench.close(workspaceId, activeId));
      return;
    }
    unawaited(
      closeFloatingTab(
        workbench: workbench,
        workspaceId: workspaceId,
        registry: registry,
        id: activeId,
        tab: tab,
        context: context,
      ),
    );
  }
}
