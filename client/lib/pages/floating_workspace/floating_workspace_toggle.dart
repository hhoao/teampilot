import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import 'floating_workspace_toggle_metrics.dart';

/// Draggable floating-workspace toggle, positioned from bottom-right.
///
/// Uses [FloatingWorkspaceState.toggleOffset] (negative insets from the
/// bottom-right corner, e.g. `Offset(-24, -72)` → 24px right / 72px bottom).
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
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

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
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark ? cs.surfaceContainerHigh : cs.workspaceCard,
                    borderRadius: BorderRadius.circular(
                      kFloatingWorkspaceToggleRadius,
                    ),
                    border: Border.all(
                      color: cs.onSurface.withValues(
                        alpha: isDark ? 0.22 : 0.12,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.55 : 0.22,
                        ),
                        blurRadius: isDark ? 16 : 12,
                        offset: Offset(0, isDark ? 6 : 4),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: kFloatingWorkspaceToggleSize,
                    height: kFloatingWorkspaceToggleSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          // Orca uses Lucide PanelsTopLeft — closest Material match.
                          Icons.space_dashboard_outlined,
                          size: kFloatingWorkspaceToggleIconSize,
                          color: cs.onSurface,
                        ),
                        if (state.attention &&
                            state.visibility ==
                                FloatingPanelVisibility.minimized)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                // Orca unread convention (amber-500).
                                color: const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? cs.surfaceContainerHigh
                                      : cs.workspaceCard,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
