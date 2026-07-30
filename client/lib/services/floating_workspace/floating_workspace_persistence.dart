import 'dart:async';

import 'package:flutter/material.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';

/// Bridges [FloatingWorkspaceCubit] geometry with [LayoutCubit] preferences.
class FloatingWorkspacePersistence {
  FloatingWorkspacePersistence({
    required LayoutCubit layout,
    required FloatingWorkspaceCubit floating,
  }) : _layout = layout,
       _floating = floating;

  final LayoutCubit _layout;
  final FloatingWorkspaceCubit _floating;
  StreamSubscription<FloatingWorkspaceState>? _subscription;
  bool _hydrating = false;

  /// Call once after layout prefs are loaded: copy floating* fields into cubit
  /// (only override cubit defaults when prefs fields are non-null).
  void hydrateFromLayout() {
    _hydrating = true;
    try {
      final prefs = _layout.state.preferences;
      final left = prefs.floatingPanelLeft;
      final top = prefs.floatingPanelTop;
      final width = prefs.floatingPanelWidth;
      final height = prefs.floatingPanelHeight;
      if (left != null && top != null && width != null && height != null) {
        _floating.setPanelBounds(Rect.fromLTWH(left, top, width, height));
      }

      final dx = prefs.floatingToggleDx;
      final dy = prefs.floatingToggleDy;
      if (dx != null && dy != null) {
        _floating.setToggleOffset(Offset(dx, dy));
      }

      _floating.setMaximized(prefs.floatingMaximized);
    } finally {
      _hydrating = false;
    }
  }

  /// Start listening to floating cubit; on panelBounds / toggleOffset /
  /// isMaximized changes, call layout setters that persist.
  void bind() {
    _subscription?.cancel();
    _subscription = _floating.stream.listen(_onFloatingStateChanged);
  }

  void _onFloatingStateChanged(FloatingWorkspaceState state) {
    if (_hydrating) return;

    final prefs = _layout.state.preferences;
    final bounds = state.panelBounds;
    final toggle = state.toggleOffset;
    if (_geometryMatches(prefs, bounds, toggle, state.isMaximized)) return;

    _layout.setFloatingWorkspaceGeometry(
      panelLeft: bounds.left,
      panelTop: bounds.top,
      panelWidth: bounds.width,
      panelHeight: bounds.height,
      toggleDx: toggle.dx,
      toggleDy: toggle.dy,
      maximized: state.isMaximized,
    );
  }

  bool _geometryMatches(
    LayoutPreferences prefs,
    Rect bounds,
    Offset toggle,
    bool maximized,
  ) {
    return prefs.floatingPanelLeft == bounds.left &&
        prefs.floatingPanelTop == bounds.top &&
        prefs.floatingPanelWidth == bounds.width &&
        prefs.floatingPanelHeight == bounds.height &&
        prefs.floatingToggleDx == toggle.dx &&
        prefs.floatingToggleDy == toggle.dy &&
        prefs.floatingMaximized == maximized;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
