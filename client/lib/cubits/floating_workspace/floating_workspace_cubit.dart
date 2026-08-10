import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import 'floating_panel_visibility.dart';
import 'floating_workspace_state.dart';

/// Panel chrome state only — visibility / placement / active workspace.
///
/// Floating tab presence / order / active are owned by
/// [WorkbenchCubit]'s per-workspace `bar.floating` strip; this cubit no longer
/// holds tab buckets. The panel resolves `FloatingTab` view data from the bar
/// by id (see `workbench_shell_run_sync.dart`).
class FloatingWorkspaceCubit extends Cubit<FloatingWorkspaceState> {
  FloatingWorkspaceCubit() : super(const FloatingWorkspaceState());

  void toggle() {
    switch (state.visibility) {
      case FloatingPanelVisibility.hidden:
        emit(
          state.copyWith(
            visibility: FloatingPanelVisibility.open,
            attention: false,
          ),
        );
      case FloatingPanelVisibility.open:
        emit(
          state.copyWith(visibility: FloatingPanelVisibility.minimized),
        );
      case FloatingPanelVisibility.minimized:
        emit(
          state.copyWith(
            visibility: FloatingPanelVisibility.open,
            attention: false,
          ),
        );
    }
  }

  void ensureOpen() {
    if (state.visibility == FloatingPanelVisibility.open) {
      if (state.attention) emit(state.copyWith(attention: false));
      return;
    }
    emit(
      state.copyWith(
        visibility: FloatingPanelVisibility.open,
        attention: false,
      ),
    );
  }

  /// Minimizes the panel. When [closeIfEmpty] is true the caller asserts the
  /// active workspace has no floating tabs, so the panel hides entirely.
  void minimize({bool closeIfEmpty = false}) {
    if (closeIfEmpty) {
      emit(state.copyWith(visibility: FloatingPanelVisibility.hidden));
      return;
    }
    emit(state.copyWith(visibility: FloatingPanelVisibility.minimized));
  }

  void setMaximized(bool value) {
    if (state.isMaximized == value) return;
    emit(state.copyWith(isMaximized: value));
  }

  void setActiveWorkspace(String id) {
    final workspaceId = id.trim();
    if (state.activeWorkspaceId == workspaceId) return;
    emit(state.copyWith(activeWorkspaceId: workspaceId));
  }

  /// Chrome cleanup when [workspaceId] closes. The tab strip for the workspace
  /// is dropped via [WorkbenchCubit.clearWorkspace]; here we only drop chrome
  /// that pointed at the closed workspace.
  void disposeWorkspace(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty) return;
    if (state.activeWorkspaceId == id) {
      emit(state.copyWith(activeWorkspaceId: ''));
    }
  }

  /// Places the panel from a host-local [rect], storing bottom-right insets.
  void setPanelRect(Rect rect, Size host) {
    if (host.width <= 0 || host.height <= 0) return;
    final placement = FloatingPanelPlacement.fromRect(rect, host);
    if (state.panelPlacement == placement &&
        state.legacyAbsoluteBounds == null) {
      return;
    }
    emit(
      state.copyWith(
        panelPlacement: placement,
        clearLegacyAbsoluteBounds: true,
      ),
    );
  }

  void setPanelPlacement(FloatingPanelPlacement placement) {
    if (state.panelPlacement == placement &&
        state.legacyAbsoluteBounds == null) {
      return;
    }
    emit(
      state.copyWith(
        panelPlacement: placement,
        clearLegacyAbsoluteBounds: true,
      ),
    );
  }

  /// Hydrate absolute left/top from older prefs; converted on first layout.
  void setLegacyAbsoluteBounds(Rect bounds) {
    emit(
      state.copyWith(
        legacyAbsoluteBounds: bounds,
        clearPanelPlacement: true,
      ),
    );
  }

  void setToggleOffset(Offset offset) {
    if (state.toggleOffset == offset) return;
    emit(state.copyWith(toggleOffset: offset));
  }

  void setAttention(bool value) {
    if (state.attention == value) return;
    emit(state.copyWith(attention: value));
  }
}
