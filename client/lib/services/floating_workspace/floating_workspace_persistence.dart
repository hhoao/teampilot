import 'dart:async';

import 'package:flutter/material.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../pages/floating_workspace/floating_workspace_toggle_metrics.dart';

/// Bridges [FloatingWorkspaceCubit] geometry with [LayoutCubit] preferences.
class FloatingWorkspacePersistence {
  FloatingWorkspacePersistence({
    required LayoutCubit layout,
    required FloatingWorkspaceCubit floating,
    this.persistDebounce = const Duration(milliseconds: 200),
  }) : _layout = layout,
       _floating = floating;

  final LayoutCubit _layout;
  final FloatingWorkspaceCubit _floating;
  final Duration persistDebounce;
  StreamSubscription<FloatingWorkspaceState>? _subscription;
  Timer? _debounce;
  bool _hydrating = false;

  /// Call once after layout prefs are loaded: copy floating* fields into cubit
  /// (only override cubit defaults when prefs fields are non-null).
  void hydrateFromLayout() {
    _hydrating = true;
    try {
      final prefs = _layout.state.preferences;
      final width = prefs.floatingPanelWidth;
      final height = prefs.floatingPanelHeight;
      final right = prefs.floatingPanelRightInset;
      final bottom = prefs.floatingPanelBottomInset;
      if (width != null && height != null && right != null && bottom != null) {
        _floating.setPanelPlacement(
          FloatingPanelPlacement(
            width: width,
            height: height,
            rightInset: right,
            bottomInset: bottom,
          ),
        );
      } else {
        final left = prefs.floatingPanelLeft;
        final top = prefs.floatingPanelTop;
        if (left != null && top != null && width != null && height != null) {
          // Pre-inset prefs: absolute host coords → convert on first layout.
          _floating.setLegacyAbsoluteBounds(
            Rect.fromLTWH(left, top, width, height),
          );
        }
      }

      final dx = prefs.floatingToggleDx;
      final dy = prefs.floatingToggleDy;
      if (dx != null && dy != null) {
        // Migrate the pre-Orca default (24/24) to Orca's 24/72 clearance.
        final offset = (dx == -24 && dy == -24)
            ? kFloatingWorkspaceToggleDefaultOffset
            : Offset(dx, dy);
        _floating.setToggleOffset(offset);
      }

      _floating.setMaximized(prefs.floatingMaximized);
    } finally {
      _hydrating = false;
    }
  }

  /// Start listening to floating cubit; on placement / toggleOffset /
  /// isMaximized changes, call layout setters that persist (debounced).
  void bind() {
    _subscription?.cancel();
    _subscription = _floating.stream.listen(_onFloatingStateChanged);
  }

  void _onFloatingStateChanged(FloatingWorkspaceState state) {
    if (_hydrating) return;

    final prefs = _layout.state.preferences;
    final placement = state.panelPlacement;
    final toggle = state.toggleOffset;
    if (placement == null) return;
    if (_geometryMatches(prefs, placement, toggle, state.isMaximized)) return;

    _debounce?.cancel();
    _debounce = Timer(persistDebounce, () {
      final latest = _floating.state;
      final p = latest.panelPlacement;
      if (p == null) return;
      _layout.setFloatingWorkspaceGeometry(
        panelWidth: p.width,
        panelHeight: p.height,
        panelRightInset: p.rightInset,
        panelBottomInset: p.bottomInset,
        toggleDx: latest.toggleOffset.dx,
        toggleDy: latest.toggleOffset.dy,
        maximized: latest.isMaximized,
      );
    });
  }

  bool _geometryMatches(
    LayoutPreferences prefs,
    FloatingPanelPlacement placement,
    Offset toggle,
    bool maximized,
  ) {
    return prefs.floatingPanelWidth == placement.width &&
        prefs.floatingPanelHeight == placement.height &&
        prefs.floatingPanelRightInset == placement.rightInset &&
        prefs.floatingPanelBottomInset == placement.bottomInset &&
        prefs.floatingToggleDx == toggle.dx &&
        prefs.floatingToggleDy == toggle.dy &&
        prefs.floatingMaximized == maximized;
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    _subscription?.cancel();
    _subscription = null;
  }
}
