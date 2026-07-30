import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/command_ids.dart';

/// Maximize / minimize window controls for the floating panel chrome.
///
/// Maximize toggles to a restore glyph while maximized (same convention as
/// the desktop window chrome). Minimize stays a distinct dash.
class FloatingWorkspaceChrome extends StatelessWidget {
  const FloatingWorkspaceChrome({
    this.onMaximize,
    this.onMinimize,
    super.key,
  });

  /// Defaults to [CommandIds.floatingMaximize] (or cubit toggle) when null.
  final VoidCallback? onMaximize;

  /// Defaults to [CommandIds.floatingMinimize] (or cubit minimize) when null.
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<FloatingWorkspaceCubit>();

    void maximize() {
      if (onMaximize != null) {
        onMaximize!();
        return;
      }
      final bus = _maybeBus(context);
      if (bus != null) {
        bus.invoke(CommandIds.floatingMaximize);
        return;
      }
      cubit.ensureOpen();
      cubit.setMaximized(!cubit.state.isMaximized);
    }

    void minimize() {
      if (onMinimize != null) {
        onMinimize!();
        return;
      }
      final bus = _maybeBus(context);
      if (bus != null) {
        bus.invoke(CommandIds.floatingMinimize);
        return;
      }
      cubit.minimize();
    }

    return BlocBuilder<FloatingWorkspaceCubit, FloatingWorkspaceState>(
      buildWhen: (a, b) => a.isMaximized != b.isMaximized,
      builder: (context, state) {
        final maximized = state.isMaximized;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TpIconButton(
              icon: maximized
                  ? Icons.filter_none
                  : Icons.crop_square_outlined,
              compact: true,
              tooltip: maximized
                  ? l10n.windowControlRestore
                  : l10n.floatingWorkspaceMaximize,
              onTap: maximize,
            ),
            TpIconButton(
              icon: Icons.horizontal_rule,
              compact: true,
              tooltip: l10n.floatingWorkspaceMinimize,
              onTap: minimize,
            ),
          ],
        );
      },
    );
  }

  static CommandBus? _maybeBus(BuildContext context) {
    try {
      return context.read<CommandBus>();
    } catch (_) {
      return null;
    }
  }
}
