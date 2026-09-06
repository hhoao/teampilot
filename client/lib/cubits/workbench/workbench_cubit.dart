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

class WorkbenchState extends Equatable {
  const WorkbenchState({this.byWorkspace = const {}});

  final Map<String, WorkspaceTabBar> byWorkspace;

  WorkspaceTabBar bar(String workspaceId) =>
      byWorkspace[workspaceId] ?? const WorkspaceTabBar();

  WorkbenchState withBar(String workspaceId, WorkspaceTabBar bar) {
    return WorkbenchState(byWorkspace: {...byWorkspace, workspaceId: bar});
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

  WorkbenchDomainPort _port;

  /// Late-wired teardown port. The app shell sets this after the domain bridge
  /// exists (the bridge is constructed after both cubits, so the no-op default
  /// is replaced once the port is available).
  set port(WorkbenchDomainPort value) => _port = value;
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
  }) => _openCenter(workspaceId, tab, preview: preview, activate: activate);

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

  /// The strip that owns [id]: prefers presence, falls back to kind-routing.
  ///
  /// File/diff previews may live on the floating strip (when the file-preview
  /// host is floating), so presence must win over `isCenterStripWorkbenchTab`.
  (TabStrip, bool) _owningStrip(WorkspaceTabBar bar, WorkbenchTabId id) {
    if (bar.center.contains(id)) return (bar.center, true);
    if (bar.floating.contains(id)) return (bar.floating, false);
    return isCenterStripWorkbenchTab(id.kind)
        ? (bar.center, true)
        : (bar.floating, false);
  }

  /// Removes [id] from the owning strip and returns it, or null if absent.
  /// The port's [WorkbenchDomainPort.onTabRemoved] is called for teardown.
  ///
  /// NOTE: `Cubit` already declares `Future<void> close()` for lifecycle, so
  /// this id-based close is declared as an override with optional positional
  /// params — `close()` (no args) performs the lifecycle close, `close(ws, id)`
  /// removes a tab and resolves to the removed id (or null when absent).
  @override
  Future<WorkbenchTabId?> close([
    String? workspaceId,
    WorkbenchTabId? id,
  ]) async {
    if (workspaceId == null || id == null) {
      await super.close();
      return null;
    }
    final bar = state.bar(workspaceId);
    final (strip, isCenter) = _owningStrip(bar, id);
    final next = _r.remove(strip, id);
    if (next == null) return null;
    emit(
      state.withBar(
        workspaceId,
        isCenter ? bar.copyWith(center: next) : bar.copyWith(floating: next),
      ),
    );
    await _port.onTabRemoved(workspaceId, id);
    return id;
  }

  /// Adds [tab] to the floating strip (shell / run / floating file or diff
  /// preview). Presence, order, active, and the preview slot are owned here.
  /// Returns the replaced preview tab id, or null when nothing was replaced.
  WorkbenchTabId? openFloating(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
    bool activate = true,
  }) {
    final bar = state.bar(workspaceId);
    final (next, replaced) = _r.add(
      bar.floating,
      tab,
      preview: preview,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
    return replaced;
  }

  void openShell(String workspaceId, String entryId, {bool activate = true}) {
    openFloating(
      workspaceId,
      WorkbenchTabId.shell(entryId),
      activate: activate,
    );
  }

  void openRun(
    String workspaceId,
    String runSessionId, {
    bool activate = true,
  }) {
    openFloating(
      workspaceId,
      WorkbenchTabId.run(runSessionId),
      activate: activate,
    );
  }

  void activate(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final (strip, isCenter) = _owningStrip(bar, id);
    final next = _r.activate(strip, id);
    emit(
      state.withBar(
        workspaceId,
        isCenter ? bar.copyWith(center: next) : bar.copyWith(floating: next),
      ),
    );
  }

  /// Reorders the floating strip for [workspaceId].
  void reorderFloating(String workspaceId, int oldIndex, int newIndex) {
    final bar = state.bar(workspaceId);
    final next = _r.reorder(bar.floating, oldIndex, newIndex);
    emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
  }

  List<WorkbenchTabId> floatingOrder(String workspaceId) =>
      state.bar(workspaceId).floating.order;

  WorkbenchTabId? floatingActiveId(String workspaceId) =>
      state.bar(workspaceId).floating.activeId;

  void pin(String workspaceId, WorkbenchTabId id) {
    _applyToOwningStrip(workspaceId, id, (strip) => _r.pin(strip, id));
  }

  /// Unpins [id] on whichever strip owns it (pinned → normal). No-op for
  /// tabs that are not pinned.
  void unpin(String workspaceId, WorkbenchTabId id) {
    _applyToOwningStrip(workspaceId, id, (strip) => _r.unpin(strip, id));
  }

  /// Promotes [id] out of preview (preview → normal) on whichever strip
  /// owns it. Dirty-edit promotion uses this — a preview slot must never
  /// replace a tab with unsaved content.
  void promote(String workspaceId, WorkbenchTabId id) {
    _applyToOwningStrip(workspaceId, id, (strip) => _r.promote(strip, id));
  }

  /// Applies [mutate] to whichever strip owns [id] (presence wins over
  /// kind-routing). No emit when the reducer returns the strip unchanged.
  void _applyToOwningStrip(
    String workspaceId,
    WorkbenchTabId id,
    TabStrip Function(TabStrip strip) mutate,
  ) {
    final bar = state.bar(workspaceId);
    final (strip, isCenter) = _owningStrip(bar, id);
    final next = mutate(strip);
    if (identical(next, strip)) return;
    emit(
      state.withBar(
        workspaceId,
        isCenter ? bar.copyWith(center: next) : bar.copyWith(floating: next),
      ),
    );
  }

  /// Shows the center landing (new-chat / start) without closing tabs.
  /// No-op when the center strip is already in landing (activeId == null) and
  /// no new initial text is supplied. A supplied text replaces the current
  /// landing prefill even when Landing is already visible. The tab active at
  /// entry is remembered as the landing's return target ([exitLanding]).
  void enterLanding(
    String workspaceId, {
    String? initialText,
    String? referencedSessionId,
  }) {
    final bar = state.bar(workspaceId);
    if (bar.center.landingActive &&
        initialText == null &&
        referencedSessionId == null) {
      return;
    }
    final next = _r.enterLanding(
      bar.center,
      initialText: initialText,
      referencedSessionId: referencedSessionId,
    );
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  /// Whether the center landing has a tab to return to (the one active before
  /// entering). Drives the landing back control's visibility.
  bool canExitLanding(String workspaceId) {
    final center = state.bar(workspaceId).center;
    final target = center.landingReturnTabId;
    return center.landingActive && target != null && center.contains(target);
  }

  /// Exits the center landing by re-activating the tab that was active before
  /// it was entered (the landing back control). No-op when not landing or
  /// when the remembered tab no longer exists — the landing then stays up,
  /// because with nothing to return to it is the workspace start page.
  void exitLanding(String workspaceId) {
    final center = state.bar(workspaceId).center;
    if (!center.landingActive) return;
    final target = center.landingReturnTabId;
    if (target == null || !center.contains(target)) return;
    activate(workspaceId, target);
  }

  /// Clears a Landing reference when its persisted Session is deleted, even
  /// when that Session never had an open workbench tab.
  void onSessionDeleted(String workspaceId, String sessionId) {
    final center = state.bar(workspaceId).center;
    if (center.landingReferenceSessionId != sessionId) return;
    emit(
      state.withBar(
        workspaceId,
        state
            .bar(workspaceId)
            .copyWith(
              center: center.copyWith(
                landingInitialText: null,
                landingInitialTextRevision:
                    center.landingInitialTextRevision + 1,
                landingReferenceSessionId: null,
              ),
            ),
      ),
    );
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

  TabStrip _removeCenterTabs(
    TabStrip center,
    Iterable<WorkbenchTabId> removed,
  ) {
    var next = center;
    for (final tab in removed) {
      next = _r.remove(next, tab) ?? next;
    }
    return next;
  }

  List<WorkbenchTabId> closeOthers(String workspaceId, WorkbenchTabId keep) {
    final bar = state.bar(workspaceId);
    final center = bar.center;
    if (!center.order.contains(keep)) return const [];
    final removed = center.order
        .where((t) => t != keep && !center.pinnedIds.contains(t))
        .toList(growable: false);
    final next = _removeCenterTabs(center, removed).copyWith(activeId: keep);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  List<WorkbenchTabId> closeRight(String workspaceId, WorkbenchTabId anchor) {
    final bar = state.bar(workspaceId);
    final center = bar.center;
    final index = center.order.indexOf(anchor);
    if (index < 0 || index >= center.order.length - 1) return const [];
    final removed = center.order
        .sublist(index + 1)
        .where((t) => !center.pinnedIds.contains(t))
        .toList(growable: false);
    final active = center.activeId;
    final nextActive = active != null && removed.contains(active)
        ? anchor
        : active;
    final next = _removeCenterTabs(
      center,
      removed,
    ).copyWith(activeId: nextActive);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  List<WorkbenchTabId> closeAll(String workspaceId) {
    final bar = state.bar(workspaceId);
    final center = bar.center;
    final removed = center.order
        .where((t) => !center.pinnedIds.contains(t))
        .toList();
    if (removed.isEmpty &&
        center.landingInitialText == null &&
        center.landingReferenceSessionId == null) {
      return const [];
    }
    var next = _removeCenterTabs(center, removed);
    if (removed.isEmpty &&
        next.landingReferenceSessionId == null &&
        next.landingInitialText != null) {
      next = next.copyWith(
        activeId: null,
        landingInitialText: null,
        landingInitialTextRevision: next.landingInitialTextRevision + 1,
      );
    }
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  void clearWorkspace(String workspaceId) {
    if (!state.byWorkspace.containsKey(workspaceId)) return;
    final next = Map<String, WorkspaceTabBar>.from(state.byWorkspace)
      ..remove(workspaceId);
    emit(WorkbenchState(byWorkspace: next));
  }
}
