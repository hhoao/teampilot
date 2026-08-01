import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import 'floating_panel_visibility.dart';
import 'floating_workspace_state.dart';

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
        emit(state.copyWith(visibility: FloatingPanelVisibility.minimized));
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

  void minimize({bool closeIfEmpty = false}) {
    if (closeIfEmpty && state.activeBucket.tabs.isEmpty) {
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

  void ensureTab(FloatingTab tab) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = state.buckets[workspaceId] ?? const FloatingWorkspaceBucket();
    final existingIndex = bucket.tabs.indexWhere((t) => t.id == tab.id);
    final tabs = List<FloatingTab>.of(bucket.tabs);
    if (existingIndex >= 0) {
      tabs[existingIndex] = tab;
    } else {
      tabs.add(tab);
    }

    final updatedBuckets = Map<String, FloatingWorkspaceBucket>.of(state.buckets)
      ..[workspaceId] = bucket.copyWith(tabs: tabs, activeTabId: tab.id);

    emit(state.copyWith(buckets: updatedBuckets));
  }

  void selectTab(String tabId) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = state.buckets[workspaceId];
    if (bucket == null || !bucket.tabs.any((t) => t.id == tabId)) return;
    if (bucket.activeTabId == tabId) return;

    final updatedBuckets = Map<String, FloatingWorkspaceBucket>.of(state.buckets)
      ..[workspaceId] = bucket.copyWith(activeTabId: tabId);

    emit(state.copyWith(buckets: updatedBuckets));
  }

  void removeTab(String tabId) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = state.buckets[workspaceId];
    if (bucket == null) return;

    final tabs = bucket.tabs.where((t) => t.id != tabId).toList();
    if (tabs.length == bucket.tabs.length) return;

    final wasActive = bucket.activeTabId == tabId;
    final nextActiveId = wasActive
        ? (tabs.isEmpty ? null : tabs.last.id)
        : bucket.activeTabId;

    final updatedBuckets = Map<String, FloatingWorkspaceBucket>.of(state.buckets);
    if (tabs.isEmpty) {
      updatedBuckets.remove(workspaceId);
    } else {
      updatedBuckets[workspaceId] = bucket.copyWith(
        tabs: tabs,
        activeTabId: nextActiveId,
        clearActiveTabId: nextActiveId == null,
      );
    }

    emit(state.copyWith(buckets: updatedBuckets));
  }

  /// Reorders tabs in the active workspace. Preserves [activeTabId].
  void reorderTabs(int oldIndex, int newIndex) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = state.buckets[workspaceId];
    if (bucket == null || bucket.tabs.isEmpty) return;

    final tabs = reorderListItems(bucket.tabs, oldIndex, newIndex);
    if (_floatingTabsEqual(tabs, bucket.tabs)) return;

    final updatedBuckets = Map<String, FloatingWorkspaceBucket>.of(state.buckets)
      ..[workspaceId] = bucket.copyWith(tabs: tabs);

    emit(state.copyWith(buckets: updatedBuckets));
  }

  static bool _floatingTabsEqual(List<FloatingTab> a, List<FloatingTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// Places the panel from a host-local [rect], storing bottom-right insets.
  void setPanelRect(Rect rect, Size host) {
    if (host.width <= 0 || host.height <= 0) return;
    final placement = FloatingPanelPlacement.fromRect(rect, host);
    if (state.panelPlacement == placement && state.legacyAbsoluteBounds == null) {
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
    if (state.panelPlacement == placement && state.legacyAbsoluteBounds == null) {
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

  void disposeWorkspace(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty || !state.buckets.containsKey(id)) return;

    final updatedBuckets = Map<String, FloatingWorkspaceBucket>.of(state.buckets)
      ..remove(id);

    emit(state.copyWith(buckets: updatedBuckets));
  }
}
