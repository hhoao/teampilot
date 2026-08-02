import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../services/floating_workspace/floating_workspace_toggle_metrics.dart';

/// Idle / hover fill for the parked launcher (Orca accent hover).
Color floatingWorkspaceToggleFill({
  required ColorScheme colorScheme,
  required Brightness brightness,
  required bool hovered,
}) {
  final idle = brightness == Brightness.dark
      ? colorScheme.surfaceContainerHigh
      : colorScheme.workspaceCard;
  if (!hovered) return idle;
  if (brightness == Brightness.dark) {
    // Orca: color-mix(accent 82%, white) ≈ ~18% white into fill.
    return Color.lerp(idle, Colors.white, 0.18)!;
  }
  return colorScheme.workspaceInset;
}

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
  var _hovered = false;
  var _dragging = false;
  var _pressed = false;

  bool get _lifted => _hovered && !_dragging && !_pressed;

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
        final brightness = Theme.of(context).brightness;
        final fill = floatingWorkspaceToggleFill(
          colorScheme: cs,
          brightness: brightness,
          hovered: _hovered,
        );
        final isDark = brightness == Brightness.dark;
        final liftFraction =
            -kFloatingWorkspaceToggleHoverLiftPx / kFloatingWorkspaceToggleSize;

        return Positioned(
          key: const Key('floating_workspace_toggle'),
          right: right,
          bottom: bottom,
          child: GestureDetector(
            onPanStart: (details) {
              _dragStartOffset = state.toggleOffset;
              _dragStartPointer = details.globalPosition;
              setState(() {
                _dragging = true;
                _pressed = true;
              });
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
              setState(() {
                _dragging = false;
                _pressed = false;
              });
            },
            onPanCancel: () {
              _dragStartOffset = null;
              _dragStartPointer = null;
              setState(() {
                _dragging = false;
                _pressed = false;
              });
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: cubit.toggle,
            child: Tooltip(
              message: l10n.floatingWorkspaceToggleTooltip,
              child: MouseRegion(
                cursor: _dragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() {
                  _hovered = false;
                  _pressed = false;
                }),
                child: AnimatedSlide(
                  offset: _lifted ? Offset(0, liftFraction) : Offset.zero,
                  duration: kFloatingWorkspaceToggleHoverDuration,
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: kFloatingWorkspaceToggleHoverDuration,
                    curve: Curves.easeOut,
                    width: kFloatingWorkspaceToggleSize,
                    height: kFloatingWorkspaceToggleSize,
                    decoration: BoxDecoration(
                      color: fill,
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
                                border: Border.all(color: fill, width: 2),
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
