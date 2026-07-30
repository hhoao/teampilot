import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../l10n/l10n_extensions.dart';

/// Draggable floating-workspace toggle (grid icon), positioned from bottom-right.
///
/// Uses [FloatingWorkspaceState.toggleOffset] (typically negative insets from
/// the bottom-right corner, e.g. `Offset(-24, -24)` → 24px inset).
class FloatingWorkspaceToggle extends StatefulWidget {
  const FloatingWorkspaceToggle({super.key});

  @override
  State<FloatingWorkspaceToggle> createState() =>
      _FloatingWorkspaceToggleState();
}

class _FloatingWorkspaceToggleState extends State<FloatingWorkspaceToggle> {
  Offset? _dragStartOffset;
  Offset? _dragStartPointer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<FloatingWorkspaceCubit, FloatingWorkspaceState>(
      buildWhen: (prev, next) =>
          prev.toggleOffset != next.toggleOffset ||
          prev.visibility != next.visibility ||
          prev.attention != next.attention,
      builder: (context, state) {
        final cubit = context.read<FloatingWorkspaceCubit>();
        final right = -state.toggleOffset.dx;
        final bottom = -state.toggleOffset.dy;

        return Positioned(
          key: const Key('floating_workspace_toggle'),
          right: right,
          bottom: bottom,
          child: GestureDetector(
            onPanStart: (details) {
              _dragStartOffset = state.toggleOffset;
              _dragStartPointer = details.globalPosition;
            },
            onPanUpdate: (details) {
              final start = _dragStartOffset;
              final pointer = _dragStartPointer;
              if (start == null || pointer == null) return;
              final delta = details.globalPosition - pointer;
              // Offset is stored as bottom-right inset (negative when inset > 0).
              // Dragging right/up decreases inset magnitude → add to dx/dy.
              cubit.setToggleOffset(
                Offset(start.dx + delta.dx, start.dy + delta.dy),
              );
            },
            onPanEnd: (_) {
              _dragStartOffset = null;
              _dragStartPointer = null;
            },
            onTap: cubit.toggle,
            child: Tooltip(
              message: l10n.floatingWorkspaceToggleTooltip,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                elevation: 2,
                shape: const CircleBorder(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.dashboard_customize_outlined,
                        size: context.tpIconSizes.md,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      if (state.attention &&
                          state.visibility ==
                              FloatingPanelVisibility.minimized)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
