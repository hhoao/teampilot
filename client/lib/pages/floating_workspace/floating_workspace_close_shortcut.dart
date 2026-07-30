import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../models/floating_workspace_tab.dart';
import '../../services/commands/key_chord.dart';
import '../../services/floating_workspace/close_floating_tab.dart';
import '../../services/floating_workspace/floating_surface_registry.dart';

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
    final bucket = cubit.state.activeBucket;
    final activeId = bucket.activeTabId;
    if (activeId == null || bucket.tabs.isEmpty) {
      cubit.minimize(closeIfEmpty: true);
      return;
    }
    FloatingTab? tab;
    for (final t in bucket.tabs) {
      if (t.id == activeId) {
        tab = t;
        break;
      }
    }
    if (tab == null) {
      cubit.minimize(closeIfEmpty: true);
      return;
    }
    unawaited(
      closeFloatingTab(
        cubit: cubit,
        registry: registry,
        tab: tab,
        context: context,
      ),
    );
  }
}
