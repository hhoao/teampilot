import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import 'floating_panel_visibility.dart';
import 'floating_workspace_state.dart';

/// A [ChangeNotifier] with a public bump so [FloatingWorkspaceCubit] (not a
/// [ChangeNotifier] subclass) can fire tab-structure changes.
class FloatingWorkspaceTabsChanged extends ChangeNotifier {
  /// Notifies listeners that tab structure changed.
  void bump() => notifyListeners();
}

/// Panel chrome state + floating tab buckets.
///
/// Two data planes with separate notification paths:
///
/// - **Chrome** (visibility / placement / workspace id / attention) goes
///   through [emit] — BlocProvider notifies every `context.select` /
///   `BlocBuilder` dependent. Low frequency.
/// - **Tabs** (buckets) are kept out of [emit]: every tab mutation would
///   `markNeedsNotifyDependents` on the whole app (Linux debug: multi-second
///   build on InheritedProviderScope alone). Tab structure changes notify
///   [tabsChanged] only — consumers that need tab data subscribe there (see
///   [FloatingWorkspaceProjection]) and read [buckets] / [activeTabFor].
class FloatingWorkspaceCubit extends Cubit<FloatingWorkspaceState> {
  FloatingWorkspaceCubit() : super(const FloatingWorkspaceState());

  Map<String, FloatingWorkspaceBucket> _buckets = const {};

  /// Bumped on tab-bucket mutations; panel / projections listen here.
  final FloatingWorkspaceTabsChanged tabsChanged = FloatingWorkspaceTabsChanged();

  Map<String, FloatingWorkspaceBucket> get buckets => _buckets;

  /// Bucket for [workspaceId], or an empty bucket when none exists yet.
  FloatingWorkspaceBucket bucketFor(String workspaceId) =>
      _buckets[workspaceId] ?? const FloatingWorkspaceBucket();

  FloatingWorkspaceBucket get activeBucket =>
      bucketFor(state.activeWorkspaceId);

  /// Active tab for [workspaceId] (only when that workspace is the active
  /// floating workspace). Consumers interpret `surfaceId` / `payload` — the
  /// cubit does not know concrete surfaces.
  FloatingTab? activeTabFor(String workspaceId) {
    if (state.activeWorkspaceId != workspaceId) return null;
    final bucket = _buckets[workspaceId] ?? const FloatingWorkspaceBucket();
    final activeId = bucket.activeTabId;
    if (activeId == null) return null;
    for (final tab in bucket.tabs) {
      if (tab.id == activeId) return tab;
    }
    return null;
  }

  void _setBuckets(Map<String, FloatingWorkspaceBucket> next) {
    _buckets = Map<String, FloatingWorkspaceBucket>.unmodifiable(next);
    tabsChanged.bump();
  }

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

  void minimize({bool closeIfEmpty = false}) {
    if (closeIfEmpty && activeBucket.tabs.isEmpty) {
      emit(
        state.copyWith(visibility: FloatingPanelVisibility.hidden),
      );
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

    final bucket = _buckets[workspaceId] ?? const FloatingWorkspaceBucket();
    final existingIndex = bucket.tabs.indexWhere((t) => t.id == tab.id);
    final tabs = List<FloatingTab>.of(bucket.tabs);
    if (existingIndex >= 0) {
      tabs[existingIndex] = tab;
    } else {
      tabs.add(tab);
    }

    _setBuckets(
      Map<String, FloatingWorkspaceBucket>.of(_buckets)
        ..[workspaceId] = bucket.copyWith(tabs: tabs, activeTabId: tab.id),
    );
  }

  void selectTab(String tabId) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = _buckets[workspaceId];
    if (bucket == null || !bucket.tabs.any((t) => t.id == tabId)) return;
    if (bucket.activeTabId == tabId) return;

    _setBuckets(
      Map<String, FloatingWorkspaceBucket>.of(_buckets)
        ..[workspaceId] = bucket.copyWith(activeTabId: tabId),
    );
  }

  void removeTab(String tabId) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = _buckets[workspaceId];
    if (bucket == null) return;

    final tabs = bucket.tabs.where((t) => t.id != tabId).toList();
    if (tabs.length == bucket.tabs.length) return;

    final wasActive = bucket.activeTabId == tabId;
    final nextActiveId = wasActive
        ? (tabs.isEmpty ? null : tabs.last.id)
        : bucket.activeTabId;

    final updatedBuckets = Map<String, FloatingWorkspaceBucket>.of(_buckets);
    if (tabs.isEmpty) {
      updatedBuckets.remove(workspaceId);
    } else {
      updatedBuckets[workspaceId] = bucket.copyWith(
        tabs: tabs,
        activeTabId: nextActiveId,
        clearActiveTabId: nextActiveId == null,
      );
    }

    _setBuckets(updatedBuckets);
  }

  /// Reorders tabs in the active workspace. Preserves [activeTabId].
  void reorderTabs(int oldIndex, int newIndex) {
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;

    final bucket = _buckets[workspaceId];
    if (bucket == null || bucket.tabs.isEmpty) return;

    final tabs = reorderListItems(bucket.tabs, oldIndex, newIndex);
    if (_floatingTabsEqual(tabs, bucket.tabs)) return;

    _setBuckets(
      Map<String, FloatingWorkspaceBucket>.of(_buckets)
        ..[workspaceId] = bucket.copyWith(tabs: tabs),
    );
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

  void disposeWorkspace(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty || !_buckets.containsKey(id)) return;

    _setBuckets(Map<String, FloatingWorkspaceBucket>.of(_buckets)..remove(id));
  }

  @override
  Future<void> close() {
    tabsChanged.dispose();
    return super.close();
  }
}
