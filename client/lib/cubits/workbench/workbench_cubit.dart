import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'tab_strip.dart';
import 'workbench_domain_port.dart';
import 'workbench_split_layout.dart';
import 'workbench_tab.dart';
import '../../utils/session/running_session_ids.dart';
import 'workbench_tab_bar.dart';

class _NoopPort implements WorkbenchDomainPort {
  const _NoopPort();
  @override
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id) async {}
}

class WorkbenchState extends Equatable {
  const WorkbenchState({this.byWorkspace = const {}});

  final Map<String, WorkspaceTabBar> byWorkspace;

  /// Cached degenerate default (the bar constructor is not const).
  static final WorkspaceTabBar _defaultBar = WorkspaceTabBar();

  WorkspaceTabBar bar(String workspaceId) =>
      byWorkspace[workspaceId] ?? _defaultBar;

  WorkbenchState withBar(String workspaceId, WorkspaceTabBar bar) {
    return WorkbenchState(byWorkspace: {...byWorkspace, workspaceId: bar});
  }

  @override
  List<Object?> get props => [byWorkspace];
}

/// Owns the workbench tab surfaces: per-workspace center + floating split
/// layouts ([WorkspaceTabBar]).
///
/// The single writer of tab presence / order / active. Domain runtimes are
/// referenced by id and reached via [WorkbenchDomainPort] on close.
///
/// Reads are focused-group scoped ([centerActiveId] etc. read the focused
/// group of the target layout); whole-surface reads go through
/// [mergedFloatingStrip]. New tabs open into the focused group of the target
/// layout (spec).
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
  static const SplitLayoutReducer _lr = SplitLayoutReducer();

  // ---- layout plumbing ----

  WorkbenchGroupLayout centerLayout(String workspaceId) =>
      state.bar(workspaceId).center;

  WorkbenchGroupLayout floatingLayout(String workspaceId) =>
      state.bar(workspaceId).floating;

  WorkbenchState _withCenter(String workspaceId, WorkbenchGroupLayout layout) =>
      state.withBar(workspaceId, state.bar(workspaceId).copyWith(center: layout));

  WorkbenchState _withFloating(
    String workspaceId,
    WorkbenchGroupLayout layout,
  ) => state.withBar(
    workspaceId,
    state.bar(workspaceId).copyWith(floating: layout),
  );

  /// The group owning [id]: presence wins over kind-routing.
  ///
  /// File/diff previews may live on the floating layout (when the file-preview
  /// host is floating), so presence must win over `isCenterStripWorkbenchTab`.
  /// When [id] is present in no group, kind-routing targets the focused group
  /// of the appropriate layout.
  (WorkbenchGroupLayout, bool, String) _owningGroup(
    WorkspaceTabBar bar,
    WorkbenchTabId id,
  ) {
    for (final e in bar.center.groups.entries) {
      if (e.value.contains(id)) return (bar.center, true, e.key);
    }
    for (final e in bar.floating.groups.entries) {
      if (e.value.contains(id)) return (bar.floating, false, e.key);
    }
    return isCenterStripWorkbenchTab(id.kind)
        ? (bar.center, true, bar.center.focusedGroupId)
        : (bar.floating, false, bar.floating.focusedGroupId);
  }

  /// Applies [mutate] to whichever group owns [id] (presence wins over
  /// kind-routing). No emit when the reducer returns the strip unchanged.
  void _mutateOwningGroup(
    String workspaceId,
    WorkbenchTabId id,
    TabStrip Function(TabStrip strip) mutate,
  ) {
    final bar = state.bar(workspaceId);
    final (layout, isCenter, groupId) = _owningGroup(bar, id);
    final next = mutate(layout.groups[groupId]!);
    if (identical(next, layout.groups[groupId])) return;
    final nextLayout = layout.copyWith(groups: {...layout.groups, groupId: next});
    emit(
      isCenter
          ? _withCenter(workspaceId, nextLayout)
          : _withFloating(workspaceId, nextLayout),
    );
  }

  /// Applies [mutate] to the focused group of the target layout. No emit when
  /// the reducer returns the strip unchanged.
  void _mutateFocusedStrip(
    String workspaceId, {
    required bool center,
    required TabStrip Function(TabStrip strip) mutate,
  }) {
    final bar = state.bar(workspaceId);
    final layout = center ? bar.center : bar.floating;
    final strip = _focusedStrip(layout);
    final next = mutate(strip);
    if (identical(next, strip)) return;
    final nextLayout = layout.copyWith(
      groups: {...layout.groups, layout.focusedGroupId: next},
    );
    emit(
      center
          ? _withCenter(workspaceId, nextLayout)
          : _withFloating(workspaceId, nextLayout),
    );
  }

  /// Runs [mutate] over one layout ([floating] selects bar.floating, else
  /// bar.center). No emit when the reducer declines (null) or returns the
  /// layout unchanged.
  void _mutateLayout(
    String workspaceId, {
    required bool floating,
    required WorkbenchGroupLayout? Function(WorkbenchGroupLayout layout) mutate,
  }) {
    final bar = state.bar(workspaceId);
    final layout = floating ? bar.floating : bar.center;
    final next = mutate(layout);
    if (next == null || identical(next, layout)) return;
    emit(
      floating
          ? _withFloating(workspaceId, next)
          : _withCenter(workspaceId, next),
    );
  }

  static String? _groupContainingTab(
    WorkbenchGroupLayout layout,
    WorkbenchTabId tab,
  ) {
    for (final entry in layout.groups.entries) {
      if (entry.value.contains(tab)) return entry.key;
    }
    return null;
  }

  static TabStrip _focusedStrip(WorkbenchGroupLayout layout) {
    final strip = layout.groups[layout.focusedGroupId];
    assert(
      strip != null,
      'focusedGroupId must address a live group (validateLayout)',
    );
    return strip ?? const TabStrip();
  }

  // ---- focused-group reads ----

  WorkbenchTabId? centerActiveId(String workspaceId) =>
      centerFocusedStrip(workspaceId).activeId;

  List<WorkbenchTabId> centerOrder(String workspaceId) =>
      centerFocusedStrip(workspaceId).order;

  TabStrip centerFocusedStrip(String workspaceId) =>
      _focusedStrip(state.bar(workspaceId).center);

  String centerFocusedGroupId(String workspaceId) =>
      state.bar(workspaceId).center.focusedGroupId;

  WorkbenchTabId? floatingActiveId(String workspaceId) =>
      floatingFocusedStrip(workspaceId).activeId;

  List<WorkbenchTabId> floatingOrder(String workspaceId) =>
      floatingFocusedStrip(workspaceId).order;

  TabStrip floatingFocusedStrip(String workspaceId) =>
      _focusedStrip(state.bar(workspaceId).floating);

  bool centerLandingActive(String workspaceId) =>
      centerFocusedStrip(workspaceId).landingActive;

  String? centerLandingInitialText(String workspaceId) =>
      centerFocusedStrip(workspaceId).landingInitialText;

  int centerLandingInitialTextRevision(String workspaceId) =>
      centerFocusedStrip(workspaceId).landingInitialTextRevision;

  String? centerLandingReferenceSessionId(String workspaceId) =>
      centerFocusedStrip(workspaceId).landingReferenceSessionId;

  /// Whole-floating-surface view: every group's tabs in depth-first leaf
  /// order, with the focused group's active tab. Consumers that mirror the
  /// entire floating panel (tab projection, bulk closes, run reconciliation)
  /// read this; the focused-group reads mirror only the focused group.
  /// Whole-surface read of the **center** layout: one strip merging every
  /// group's tabs in leaf order (active id from the focused group, preview /
  /// pinned ids unioned). Sidebar "open sessions" and other whole-surface
  /// consumers use this so tabs in non-focused groups stay visible.
  TabStrip mergedCenterStrip(String workspaceId) =>
      _mergeGroupStrips(centerLayout(workspaceId));

  /// Per-split-group session tile data in leaf order:
  /// (groupId, that group's non-preview session tab ids). Empty for a
  /// single-group layout — callers keep the flat path. Groups whose tabs
  /// are all non-session (files / diffs) are omitted.
  List<(String, List<String>)> centerSessionGroups(String workspaceId) {
    final layout = centerLayout(workspaceId);
    if (layout.groups.length == 1) return const [];
    final result = <(String, List<String>)>[];
    for (final groupId in layout.leafGroupIds) {
      final strip = layout.groups[groupId];
      if (strip == null) continue;
      final sessionIds = OpenSessionTabIds.fromCenterBarOrder(
        strip.order,
        previewIds: strip.previewIds,
      ).ids;
      if (sessionIds.isEmpty) continue;
      result.add((groupId, sessionIds));
    }
    return result;
  }

  TabStrip mergedFloatingStrip(String workspaceId) =>
      _mergeGroupStrips(floatingLayout(workspaceId));

  TabStrip _mergeGroupStrips(WorkbenchGroupLayout layout) {
    if (layout.groups.length == 1) {
      // Degenerate single group: keep the strip as-is (landing fields too).
      return layout.groups.values.single;
    }
    final order = <WorkbenchTabId>[];
    final previews = <WorkbenchTabId>{};
    final pinneds = <WorkbenchTabId>{};
    for (final groupId in layout.leafGroupIds) {
      final strip = layout.groups[groupId];
      if (strip == null) continue;
      order.addAll(strip.order);
      previews.addAll(strip.previewIds);
      pinneds.addAll(strip.pinnedIds);
    }
    return TabStrip(
      order: order,
      activeId: _focusedStrip(layout).activeId,
      previewIds: previews,
      pinnedIds: pinneds,
    );
  }

  // ---- open ----

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
    return _openIntoLayout(
      workspaceId,
      tab,
      center: true,
      preview: preview,
      activate: activate,
    );
  }

  /// Adds [tab] into the focused group of the target layout — or, when the
  /// tab is already hosted by another group of that layout, into that group
  /// (and focuses it), so no tab ever appears in two groups. Returns the
  /// replaced preview tab id, or null when nothing was replaced.
  WorkbenchTabId? _openIntoLayout(
    String workspaceId,
    WorkbenchTabId tab, {
    required bool center,
    required bool preview,
    bool activate = true,
  }) {
    final bar = state.bar(workspaceId);
    final layout = center ? bar.center : bar.floating;
    var targetGroupId = layout.focusedGroupId;
    for (final e in layout.groups.entries) {
      if (e.value.contains(tab)) {
        targetGroupId = e.key;
        break;
      }
    }
    final (next, replaced) = _r.add(
      layout.groups[targetGroupId]!,
      tab,
      preview: preview,
      activate: activate,
    );
    final nextLayout = layout.copyWith(
      groups: {...layout.groups, targetGroupId: next},
      focusedGroupId: targetGroupId,
    );
    emit(
      center
          ? _withCenter(workspaceId, nextLayout)
          : _withFloating(workspaceId, nextLayout),
    );
    return replaced;
  }

  /// Adds [tab] to the floating layout's focused group (shell / run / floating
  /// file or diff preview). Presence, order, active, and the preview slot are
  /// owned here. Returns the replaced preview tab id, or null when nothing
  /// was replaced.
  WorkbenchTabId? openFloating(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
    bool activate = true,
  }) => _openIntoLayout(
    workspaceId,
    tab,
    center: false,
    preview: preview,
    activate: activate,
  );

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

  // ---- close ----

  /// Removes [id] from the layout that owns it (whole-layout reducer remove:
  /// a group emptied by the removal is pruned) and returns it, or null if
  /// absent. The port's [WorkbenchDomainPort.onTabRemoved] is called for
  /// teardown.
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
    final nextCenter = _lr.remove(bar.center, id);
    if (nextCenter != null) {
      emit(_withCenter(workspaceId, nextCenter));
      await _port.onTabRemoved(workspaceId, id);
      return id;
    }
    final nextFloating = _lr.remove(bar.floating, id);
    if (nextFloating != null) {
      emit(_withFloating(workspaceId, nextFloating));
      await _port.onTabRemoved(workspaceId, id);
      return id;
    }
    return null;
  }

  // ---- strip-level mutations ----

  /// Activates [id] within its owning group and focuses that group. No-op
  /// when the tab is absent from both layouts.
  void activate(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final nextCenter = _lr.activate(bar.center, id);
    if (!identical(nextCenter, bar.center)) {
      emit(_withCenter(workspaceId, nextCenter));
      return;
    }
    final nextFloating = _lr.activate(bar.floating, id);
    if (!identical(nextFloating, bar.floating)) {
      emit(_withFloating(workspaceId, nextFloating));
    }
  }

  /// Reorders the center layout's focused group for [workspaceId].
  void reorder(String workspaceId, int oldIndex, int newIndex) {
    _mutateFocusedStrip(
      workspaceId,
      center: true,
      mutate: (strip) => _r.reorder(strip, oldIndex, newIndex),
    );
  }

  /// Reorders the floating layout's focused group for [workspaceId].
  void reorderFloating(String workspaceId, int oldIndex, int newIndex) {
    _mutateFocusedStrip(
      workspaceId,
      center: false,
      mutate: (strip) => _r.reorder(strip, oldIndex, newIndex),
    );
  }

  void pin(String workspaceId, WorkbenchTabId id) {
    _mutateOwningGroup(workspaceId, id, (strip) => _r.pin(strip, id));
  }

  /// Unpins [id] on whichever group owns it (pinned → normal). No-op for
  /// tabs that are not pinned.
  void unpin(String workspaceId, WorkbenchTabId id) {
    _mutateOwningGroup(workspaceId, id, (strip) => _r.unpin(strip, id));
  }

  /// Promotes [id] out of preview (preview → normal) on whichever group owns
  /// it. Dirty-edit promotion uses this — a preview slot must never replace a
  /// tab with unsaved content.
  void promote(String workspaceId, WorkbenchTabId id) {
    _mutateOwningGroup(workspaceId, id, (strip) => _r.promote(strip, id));
  }

  // ---- landing ----

  /// Shows the focused center group's landing (new-chat / start) without
  /// closing tabs. No-op when that group is already in landing
  /// (activeId == null) and no new initial text is supplied. A supplied text
  /// replaces the current landing prefill even when Landing is already
  /// visible. The tab active at entry is remembered as the landing's return
  /// target ([exitLanding]).
  void enterLanding(
    String workspaceId, {
    String? initialText,
    String? referencedSessionId,
  }) {
    _mutateFocusedStrip(
      workspaceId,
      center: true,
      mutate: (strip) {
        if (strip.landingActive &&
            initialText == null &&
            referencedSessionId == null) {
          return strip;
        }
        return _r.enterLanding(
          strip,
          initialText: initialText,
          referencedSessionId: referencedSessionId,
        );
      },
    );
  }

  /// Whether the focused center group's landing has a tab to return to (the
  /// one active before entering). Drives the landing back control's
  /// visibility.
  bool canExitLanding(String workspaceId) {
    final center = centerFocusedStrip(workspaceId);
    final target = center.landingReturnTabId;
    return center.landingActive && target != null && center.contains(target);
  }

  /// Exits the focused center group's landing by re-activating the tab that
  /// was active before it was entered (the landing back control). No-op when
  /// not landing or when the remembered tab no longer exists — the landing
  /// then stays up, because with nothing to return to it is the workspace
  /// start page.
  void exitLanding(String workspaceId) {
    final center = centerFocusedStrip(workspaceId);
    if (!center.landingActive) return;
    final target = center.landingReturnTabId;
    if (target == null || !center.contains(target)) return;
    activate(workspaceId, target);
  }

  /// Clears a Landing reference when its persisted Session is deleted, even
  /// when that Session never had an open workbench tab.
  void onSessionDeleted(String workspaceId, String sessionId) {
    _mutateFocusedStrip(
      workspaceId,
      center: true,
      mutate: (strip) {
        if (strip.landingReferenceSessionId != sessionId) return strip;
        return strip.copyWith(
          landingInitialText: null,
          landingInitialTextRevision: strip.landingInitialTextRevision + 1,
          landingReferenceSessionId: null,
        );
      },
    );
  }

  // ---- bulk closes ----

  static TabStrip _removeTabs(TabStrip strip, Iterable<WorkbenchTabId> removed) {
    var next = strip;
    for (final tab in removed) {
      next = _r.remove(next, tab) ?? next;
    }
    return next;
  }

  String? _centerGroupContaining(String workspaceId, WorkbenchTabId tab) =>
      _groupContainingTab(state.bar(workspaceId).center, tab);

  /// Closes every non-pinned tab of [keep]'s owning center group, keeping
  /// [keep] active. The owning group (the tab's context menu), not the
  /// focused group.
  List<WorkbenchTabId> closeOthers(String workspaceId, WorkbenchTabId keep) {
    final bar = state.bar(workspaceId);
    final layout = bar.center;
    final groupId = _centerGroupContaining(workspaceId, keep);
    if (groupId == null) return const [];
    final strip = layout.groups[groupId]!;
    final removed = strip.order
        .where((t) => t != keep && !strip.pinnedIds.contains(t))
        .toList(growable: false);
    final next = _removeTabs(strip, removed).copyWith(activeId: keep);
    emit(
      _withCenter(
        workspaceId,
        layout.copyWith(groups: {...layout.groups, groupId: next}),
      ),
    );
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  /// Closes the non-pinned tabs to the right of [anchor] within [anchor]'s
  /// owning center group. The owning group (the tab's context menu), not the
  /// focused group.
  List<WorkbenchTabId> closeRight(String workspaceId, WorkbenchTabId anchor) {
    final bar = state.bar(workspaceId);
    final layout = bar.center;
    final groupId = _centerGroupContaining(workspaceId, anchor);
    if (groupId == null) return const [];
    final strip = layout.groups[groupId]!;
    final index = strip.order.indexOf(anchor);
    if (index < 0 || index >= strip.order.length - 1) return const [];
    final removed = strip.order
        .sublist(index + 1)
        .where((t) => !strip.pinnedIds.contains(t))
        .toList(growable: false);
    final active = strip.activeId;
    final nextActive = active != null && removed.contains(active)
        ? anchor
        : active;
    final next = _removeTabs(strip, removed).copyWith(activeId: nextActive);
    emit(
      _withCenter(
        workspaceId,
        layout.copyWith(groups: {...layout.groups, groupId: next}),
      ),
    );
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  /// Closes every non-pinned tab of the focused center group (group-scoped,
  /// spec): pinned tabs of the focused group survive, and other groups are
  /// untouched. A group emptied by the closes is pruned (sole root may go
  /// degenerate-empty instead).
  List<WorkbenchTabId> closeAll(String workspaceId) {
    final bar = state.bar(workspaceId);
    final layout = bar.center;
    final focusedId = layout.focusedGroupId;
    final strip = layout.groups[focusedId]!;
    final removed = strip.order
        .where((t) => !strip.pinnedIds.contains(t))
        .toList();
    if (removed.isEmpty &&
        strip.landingInitialText == null &&
        strip.landingReferenceSessionId == null) {
      return const [];
    }
    var nextLayout = layout;
    for (final tab in removed) {
      nextLayout = _lr.remove(nextLayout, tab) ?? nextLayout;
    }
    if (removed.isEmpty && nextLayout.groups.containsKey(focusedId)) {
      final next = nextLayout.groups[focusedId]!;
      if (next.landingReferenceSessionId == null &&
          next.landingInitialText != null) {
        nextLayout = nextLayout.copyWith(
          groups: {
            ...nextLayout.groups,
            focusedId: next.copyWith(
              activeId: null,
              landingInitialText: null,
              landingInitialTextRevision: next.landingInitialTextRevision + 1,
            ),
          },
        );
      }
    }
    emit(_withCenter(workspaceId, nextLayout));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  // ---- split-group mutations ----

  /// Splits [tab] out of its group into a new sibling group (reducer
  /// `split`). Silent no-op when the reducer declines (absent tab, or the
  /// sole tab of its group — that group would empty).
  void splitTab(
    String workspaceId,
    WorkbenchTabId tab, {
    required Axis axis,
    required bool before,
    bool floating = false,
  }) => _mutateLayout(
    workspaceId,
    floating: floating,
    mutate: (layout) => _lr.split(layout, tab: tab, axis: axis, before: before),
  );

  /// Same split semantics as [splitTab], but the new sibling group is placed
  /// adjacent to [targetGroupId] instead of the tab's owning group.
  void splitInto(
    String workspaceId,
    WorkbenchTabId tab,
    String targetGroupId, {
    required Axis axis,
    required bool before,
    bool floating = false,
  }) => _mutateLayout(
    workspaceId,
    floating: floating,
    mutate: (layout) => _lr.splitInto(
      layout,
      tab: tab,
      targetGroupId: targetGroupId,
      axis: axis,
      before: before,
    ),
  );

  /// Moves [tab] into [targetGroupId] (appended, activated) and focuses the
  /// target. No-op when the reducer declines.
  void moveTab(
    String workspaceId,
    WorkbenchTabId tab,
    String targetGroupId, {
    bool floating = false,
  }) => _mutateLayout(
    workspaceId,
    floating: floating,
    mutate: (layout) => _lr.moveTab(layout, tab: tab, targetGroupId: targetGroupId),
  );

  /// Focuses [groupId] on the target layout. No-op when it is not a live
  /// leaf.
  void focusGroup(String workspaceId, String groupId, {bool floating = false}) =>
      _mutateLayout(
        workspaceId,
        floating: floating,
        mutate: (layout) => _lr.focusGroup(layout, groupId),
      );

  /// VSCode "Open to the Side": reveals [tab] in a group beside the focused
  /// one along [axis] ([before] = left/up side). Reuses the adjacent group
  /// when one exists (a source group emptied by the move is pruned);
  /// otherwise splits a new sibling group off the focused group. A tab that
  /// is the sole tab of another group still lands in a new sibling via a
  /// two-step move + split. Only when no side-by-side view is possible at
  /// all (the tab is the sole content of the whole layout, or the focused
  /// group is empty) does this degrade to activating and focusing the tab's
  /// own group. Center layout only.
  void revealTabBeside(
    String workspaceId,
    WorkbenchTabId tab, {
    required Axis axis,
    required bool before,
  }) {
    final layout = centerLayout(workspaceId);
    final focused = layout.focusedGroupId;
    final adjacent = adjacentLeaf(layout, focused, axis: axis, before: before);
    if (adjacent != null) {
      moveTab(workspaceId, tab, adjacent);
      return;
    }
    // No neighbor on that side: try to split the tab out of its own group
    // into a new sibling beside the focused group.
    final split = _lr.splitInto(
      layout,
      tab: tab,
      targetGroupId: focused,
      axis: axis,
      before: before,
    );
    if (split != null) {
      _mutateLayout(workspaceId, floating: false, mutate: (_) => split);
      return;
    }
    // The tab cannot donate (sole tab of its group): move it into the
    // focused group first, then split it right back out beside it — the net
    // effect is a new sibling group holding the tab, with the emptied source
    // group pruned. Requires the focused group to already host a tab (the
    // split below needs a survivor).
    final owner = _groupContainingTab(layout, tab);
    final focusedStrip = layout.groups[focused];
    if (owner != null &&
        owner != focused &&
        focusedStrip != null &&
        focusedStrip.order.isNotEmpty) {
      moveTab(workspaceId, tab, focused);
      splitTab(workspaceId, tab, axis: axis, before: before);
      return;
    }
    // Degenerate fallback: activate + focus the tab's own group.
    _mutateLayout(
      workspaceId,
      floating: false,
      mutate: (current) => _lr.moveTab(
        current,
        tab: tab,
        targetGroupId:
            _groupContainingTab(current, tab) ?? current.focusedGroupId,
      ),
    );
  }

  /// Commits a resize of the split branch at [path] (sequence of
  /// second/first choices from the root) to [fraction] (clamped). No-op when
  /// the path addresses a leaf or walks off the tree.
  void commitSplitResize(
    String workspaceId, {
    required List<bool> path,
    required double fraction,
    bool floating = false,
  }) => _mutateLayout(
    workspaceId,
    floating: floating,
    mutate: (layout) =>
        _lr.commitResizeByPath(layout, path: path, fraction: fraction),
  );

  /// Maximizes [groupId], or restores it when already maximized. No-op when
  /// it is not a live leaf.
  void toggleMaximizeGroup(
    String workspaceId,
    String groupId, {
    bool floating = false,
  }) => _mutateLayout(
    workspaceId,
    floating: floating,
    mutate: (layout) => _lr.toggleMaximize(layout, groupId),
  );

  /// Resets the target layout to a single group holding every tab in stable
  /// depth-first order.
  void collapseSplitLayout(String workspaceId, {bool floating = false}) =>
      _mutateLayout(
        workspaceId,
        floating: floating,
        mutate: _lr.collapse,
      );

  /// Restores both layouts from persisted snapshots (Task 9 restore entry).
  /// Null arguments keep the current layout of that surface.
  void resetLayoutToSnapshot(
    String workspaceId,
    WorkbenchGroupLayout? center,
    WorkbenchGroupLayout? floating,
  ) {
    final bar = state.bar(workspaceId);
    emit(
      state.withBar(
        workspaceId,
        bar.copyWith(
          center: center ?? bar.center,
          floating: floating ?? bar.floating,
        ),
      ),
    );
  }

  // ---- workspace lifecycle ----

  void clearWorkspace(String workspaceId) {
    if (!state.byWorkspace.containsKey(workspaceId)) return;
    final next = Map<String, WorkspaceTabBar>.from(state.byWorkspace)
      ..remove(workspaceId);
    emit(WorkbenchState(byWorkspace: next));
  }
}
