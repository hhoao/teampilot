import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'tab_strip.dart';
import 'workbench_domain_port.dart';
import 'workbench_tab.dart';
import 'workbench_tab_bar.dart';

class _NoopPort implements WorkbenchDomainPort {
  const _NoopPort();
  @override
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id) async {}
}

/// Back-compat facade over [WorkspaceTabBar.center] so existing readers of the
/// old `bucket(ws).tabOrder` surface keep compiling during migration. Deleted
/// with the wrapper methods in Task 5.
class WorkbenchWorkspaceState extends Equatable {
  const WorkbenchWorkspaceState(this.bar);

  final WorkspaceTabBar bar;

  List<WorkbenchTabId> get tabOrder => bar.center.order;
  WorkbenchTabId? get activeTabId => bar.center.activeId;
  Set<WorkbenchTabId> get previewTabIds => bar.center.previewIds;
  bool get welcomeActive => bar.center.landingActive;
  bool isPreview(WorkbenchTabId tab) => bar.center.previewIds.contains(tab);

  /// Back-compat: the migrate path (`migrate_legacy_workbench_tabs`) builds a
  /// center strip with shell/run tabs via `copyWith(tabOrder: [...])`. Rewrites
  /// the underlying center strip. Deleted with the facade in Task 6.
  WorkbenchWorkspaceState copyWith({
    List<WorkbenchTabId>? tabOrder,
    WorkbenchTabId? activeTabId,
    Set<WorkbenchTabId>? previewTabIds,
    bool? welcomeActive,
    bool clearActive = false,
  }) {
    final order = tabOrder ?? bar.center.order;
    var active = clearActive ? null : (activeTabId ?? bar.center.activeId);
    if (welcomeActive == true) active = null;
    return WorkbenchWorkspaceState(
      bar.copyWith(
        center: TabStrip(
          order: order,
          activeId: active,
          previewIds: previewTabIds ?? bar.center.previewIds,
        ),
      ),
    );
  }

  @override
  List<Object?> get props => [bar];
}

class WorkbenchState extends Equatable {
  const WorkbenchState({this.byWorkspace = const {}});

  final Map<String, WorkspaceTabBar> byWorkspace;

  WorkspaceTabBar bar(String workspaceId) =>
      byWorkspace[workspaceId] ?? const WorkspaceTabBar();

  /// Back-compat facade (Task 5 removes callers of this).
  WorkbenchWorkspaceState bucket(String workspaceId) =>
      WorkbenchWorkspaceState(bar(workspaceId));

  WorkbenchState withBar(String workspaceId, WorkspaceTabBar bar) {
    return WorkbenchState(byWorkspace: {...byWorkspace, workspaceId: bar});
  }

  /// Back-compat: the migrate path (`migrate_legacy_workbench_tabs`) writes
  /// buckets via `withBucket`. Deleted with the facade in Task 6.
  WorkbenchState withBucket(String workspaceId, WorkbenchWorkspaceState bucket) {
    return WorkbenchState(byWorkspace: {...byWorkspace, workspaceId: bucket.bar});
  }

  @override
  List<Object?> get props => [byWorkspace];
}

/// Owns the workbench tab bar: per-workspace center + floating strips.
///
/// The single writer of tab presence / order / active. Domain runtimes are
/// referenced by id and reached via [WorkbenchDomainPort] on close.
class WorkbenchCubit extends Cubit<WorkbenchState> {
  WorkbenchCubit({WorkbenchDomainPort? port})
      : _port = port ?? const _NoopPort(),
        super(const WorkbenchState());

  final WorkbenchDomainPort _port;
  static const TabStripReducer _r = TabStripReducer();

  // ---- NEW core API ----

  WorkbenchTabId? openSession(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) => _openCenter(
    workspaceId,
    WorkbenchTabId.session(sessionId),
    preview: preview,
    activate: activate,
  );

  WorkbenchTabId? openFile(
    String workspaceId,
    String path, {
    bool preview = false,
    bool activate = true,
  }) => _openCenter(
    workspaceId,
    WorkbenchTabId.file(path),
    preview: preview,
    activate: activate,
  );

  WorkbenchTabId? openDiff(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
    bool activate = true,
  }) => _openCenter(
    workspaceId,
    tab,
    preview: preview,
    activate: activate,
  );

  WorkbenchTabId? _openCenter(
    String workspaceId,
    WorkbenchTabId tab, {
    required bool preview,
    bool activate = true,
  }) {
    if (!isCenterStripWorkbenchTab(tab.kind)) return null;
    final bar = state.bar(workspaceId);
    final (next, replaced) = _r.add(
      bar.center,
      tab,
      preview: preview,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
    return replaced;
  }

  /// Removes [id] from the owning strip and returns it, or null if absent.
  /// The port's [WorkbenchDomainPort.onTabRemoved] is called for teardown.
  ///
  /// NOTE: `Cubit` already declares `Future<void> close()` for lifecycle, so
  /// this id-based close is declared as an override with optional positional
  /// params — `close()` (no args) performs the lifecycle close, `close(ws, id)`
  /// removes a tab and resolves to the removed id (or null when absent).
  @override
  Future<WorkbenchTabId?> close([String? workspaceId, WorkbenchTabId? id]) async {
    if (workspaceId == null || id == null) {
      await super.close();
      return null;
    }
    final bar = state.bar(workspaceId);
    final isCenter = isCenterStripWorkbenchTab(id.kind);
    final strip = isCenter ? bar.center : bar.floating;
    final next = _r.remove(strip, id);
    if (next == null) return null;
    emit(state.withBar(
      workspaceId,
      isCenter ? bar.copyWith(center: next) : bar.copyWith(floating: next),
    ));
    await _port.onTabRemoved(workspaceId, id);
    return id;
  }

  void openShell(String workspaceId, String entryId, {bool activate = true}) {
    final bar = state.bar(workspaceId);
    final (next, _) = _r.add(
      bar.floating,
      WorkbenchTabId.shell(entryId),
      preview: false,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
  }

  void openRun(String workspaceId, String runSessionId, {bool activate = true}) {
    final bar = state.bar(workspaceId);
    final (next, _) = _r.add(
      bar.floating,
      WorkbenchTabId.run(runSessionId),
      preview: false,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
  }

  void activate(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final strip = isCenterStripWorkbenchTab(id.kind) ? bar.center : bar.floating;
    final next = _r.activate(strip, id);
    emit(state.withBar(
      workspaceId,
      isCenterStripWorkbenchTab(id.kind)
          ? bar.copyWith(center: next)
          : bar.copyWith(floating: next),
    ));
  }

  void pin(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final next = _r.pin(bar.center, id);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  /// Shows the center landing (new-chat / welcome) without closing tabs.
  void enterLanding(String workspaceId) {
    final bar = state.bar(workspaceId);
    final next = _r.enterLanding(bar.center);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  void reorder(String workspaceId, int oldIndex, int newIndex) {
    final bar = state.bar(workspaceId);
    final next = _r.reorder(bar.center, oldIndex, newIndex);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  List<WorkbenchTabId> centerOrder(String workspaceId) =>
      state.bar(workspaceId).center.order;

  WorkbenchTabId? centerActiveId(String workspaceId) =>
      state.bar(workspaceId).center.activeId;

  // ---- Legacy wrappers (deleted in Task 5; keep callers compiling) ----

  WorkbenchTabId? ensureTab(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
  }) => _openCenter(workspaceId, tab, preview: preview, activate: true);

  /// Legacy close. Unlike the new kind-routed [close], this removes from the
  /// center strip regardless of kind — the migrate path injects shell/run tabs
  /// into the center via the facade and relies on that. Deleted in Task 6.
  void removeTab(String workspaceId, WorkbenchTabId tab) {
    final bar = state.bar(workspaceId);
    final next = _r.remove(bar.center, tab);
    if (next == null) return;
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
    unawaited(_port.onTabRemoved(workspaceId, tab));
  }

  void select(String workspaceId, WorkbenchTabId tab) =>
      activate(workspaceId, tab);

  void reorderTabs(String workspaceId, int oldIndex, int newIndex) =>
      reorder(workspaceId, oldIndex, newIndex);

  void pinTab(String workspaceId, WorkbenchTabId tab) =>
      pin(workspaceId, tab);

  void clearActive(String workspaceId) => enterLanding(workspaceId);

  void enterWelcome(String workspaceId) => enterLanding(workspaceId);

  List<WorkbenchTabId> closeOthers(String workspaceId, WorkbenchTabId keep) {
    final bar = state.bar(workspaceId);
    final center = bar.center;
    if (!center.order.contains(keep)) return const [];
    final removed = center.order.where((t) => t != keep).toList(growable: false);
    emit(state.withBar(
      workspaceId,
      bar.copyWith(
        center: TabStrip(
          order: [keep],
          activeId: keep,
          previewIds: center.previewIds.contains(keep)
              ? {keep}
              : const <WorkbenchTabId>{},
        ),
      ),
    ));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  List<WorkbenchTabId> closeRight(String workspaceId, WorkbenchTabId anchor) {
    final center = state.bar(workspaceId).center;
    final index = center.order.indexOf(anchor);
    if (index < 0 || index >= center.order.length - 1) return const [];
    final kept = center.order.sublist(0, index + 1);
    final removed = center.order.sublist(index + 1);
    final active = center.activeId;
    final nextActive = active != null && removed.contains(active) ? anchor : active;
    emit(state.withBar(
      workspaceId,
      state.bar(workspaceId).copyWith(
        center: TabStrip(
          order: kept,
          activeId: nextActive,
          previewIds: center.previewIds.where(kept.contains).toSet(),
        ),
      ),
    ));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  List<WorkbenchTabId> closeAll(String workspaceId) {
    final center = state.bar(workspaceId).center;
    final removed = List<WorkbenchTabId>.from(center.order);
    if (removed.isEmpty) return const [];
    emit(state.withBar(
      workspaceId,
      state.bar(workspaceId).copyWith(center: const TabStrip()),
    ));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  /// Legacy reconcile-by-append. Kept ONLY until Task 3 deletes it together
  /// with [WorkbenchSessionSync]; the bridge then feeds the bar directly.
  void syncSessions(
    String workspaceId,
    List<String> sessionIds, {
    String? preferredActiveSessionId,
    bool newChatActive = false,
  }) {
    final bar = state.bar(workspaceId);
    final sessionSet = sessionIds.toSet();
    final order = <WorkbenchTabId>[];
    for (final tab in bar.center.order) {
      if (!isCenterStripWorkbenchTab(tab.kind)) continue;
      if (tab.kind == WorkbenchTabKind.session) {
        if (sessionSet.contains(tab.id)) order.add(tab);
      } else {
        order.add(tab);
      }
    }
    final existingSessions = {
      for (final t in order)
        if (t.kind == WorkbenchTabKind.session) t.id,
    };
    for (final id in sessionIds) {
      if (!existingSessions.contains(id)) {
        order.add(WorkbenchTabId.session(id));
      }
    }
    var active = bar.center.activeId;
    if (newChatActive) {
      active = null;
    } else if (active != null && !order.contains(active)) {
      active = null;
    }
    emit(state.withBar(
      workspaceId,
      bar.copyWith(
        center: TabStrip(
          order: order,
          activeId: active,
          previewIds: bar.center.previewIds.where(order.contains).toSet(),
        ),
      ),
    ));
  }

  void clearWorkspace(String workspaceId) {
    if (!state.byWorkspace.containsKey(workspaceId)) return;
    final next = Map<String, WorkspaceTabBar>.from(state.byWorkspace)
      ..remove(workspaceId);
    emit(WorkbenchState(byWorkspace: next));
  }

  List<WorkbenchTabId> tabOrder(String workspaceId) => centerOrder(workspaceId);

  WorkbenchTabId? activeTabId(String workspaceId) =>
      centerActiveId(workspaceId);

  bool welcomeActive(String workspaceId) =>
      state.bar(workspaceId).center.landingActive;
}
