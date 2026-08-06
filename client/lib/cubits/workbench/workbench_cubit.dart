import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import 'workbench_tab.dart';

class WorkbenchWorkspaceState extends Equatable {
  const WorkbenchWorkspaceState({
    this.tabOrder = const [],
    this.activeTabId,
    this.previewTabIds = const {},
    this.lastFocusedShellTabId,
    this.welcomeActive = false,
  });

  final List<WorkbenchTabId> tabOrder;
  final WorkbenchTabId? activeTabId;

  /// Tabs that are still preview (replaceable) until pinned.
  ///
  /// Shared across session / file / diff — at most one preview slot.
  final Set<WorkbenchTabId> previewTabIds;

  /// Last shell tab the user focused in this workspace (for re-open).
  final WorkbenchTabId? lastFocusedShellTabId;

  /// User explicitly entered the welcome/start empty center (e.g. landing ←).
  /// While true, [WorkbenchCubit.syncSessions] must not auto-select a session.
  final bool welcomeActive;

  bool isPreview(WorkbenchTabId tab) => previewTabIds.contains(tab);

  WorkbenchWorkspaceState copyWith({
    List<WorkbenchTabId>? tabOrder,
    WorkbenchTabId? activeTabId,
    Set<WorkbenchTabId>? previewTabIds,
    WorkbenchTabId? lastFocusedShellTabId,
    bool? welcomeActive,
    bool clearActive = false,
  }) {
    return WorkbenchWorkspaceState(
      tabOrder: tabOrder ?? this.tabOrder,
      activeTabId: clearActive ? null : (activeTabId ?? this.activeTabId),
      previewTabIds: previewTabIds ?? this.previewTabIds,
      lastFocusedShellTabId:
          lastFocusedShellTabId ?? this.lastFocusedShellTabId,
      welcomeActive: welcomeActive ?? this.welcomeActive,
    );
  }

  @override
  List<Object?> get props => [
    tabOrder,
    activeTabId,
    previewTabIds,
    lastFocusedShellTabId,
    welcomeActive,
  ];
}

class WorkbenchState extends Equatable {
  const WorkbenchState({this.byWorkspace = const {}});

  final Map<String, WorkbenchWorkspaceState> byWorkspace;

  WorkbenchWorkspaceState bucket(String workspaceId) =>
      byWorkspace[workspaceId] ?? const WorkbenchWorkspaceState();

  WorkbenchState withBucket(
    String workspaceId,
    WorkbenchWorkspaceState bucket,
  ) {
    return WorkbenchState(byWorkspace: {...byWorkspace, workspaceId: bucket});
  }

  @override
  List<Object?> get props => [byWorkspace];
}

/// Owns center-bar [tabOrder] and [activeTabId] per title-bar workspace.
class WorkbenchCubit extends Cubit<WorkbenchState> {
  WorkbenchCubit() : super(const WorkbenchState());

  List<WorkbenchTabId> tabOrder(String workspaceId) =>
      state.bucket(workspaceId).tabOrder;

  WorkbenchTabId? activeTabId(String workspaceId) =>
      state.bucket(workspaceId).activeTabId;

  bool welcomeActive(String workspaceId) =>
      state.bucket(workspaceId).welcomeActive;

  bool isPreview(String workspaceId, WorkbenchTabId tab) =>
      state.bucket(workspaceId).isPreview(tab);

  WorkbenchTabId? lastFocusedShellTabId(String workspaceId) =>
      state.bucket(workspaceId).lastFocusedShellTabId;

  WorkbenchTabId? resolveMostRecentShell(String workspaceId) {
    final bucket = state.bucket(workspaceId);
    final last = bucket.lastFocusedShellTabId;
    if (last != null &&
        last.kind == WorkbenchTabKind.shell &&
        bucket.tabOrder.contains(last)) {
      return last;
    }
    for (var i = bucket.tabOrder.length - 1; i >= 0; i--) {
      if (bucket.tabOrder[i].kind == WorkbenchTabKind.shell) {
        return bucket.tabOrder[i];
      }
    }
    return null;
  }

  /// Ensures [tab] is in the bar and active.
  ///
  /// When [preview] is true and another preview exists (any kind), that preview
  /// is replaced in-place and returned so callers can close its domain state.
  /// When [preview] is false, the tab is permanent (pinned).
  ///
  /// If [tab] already exists as a permanent tab and [preview] is true, it is
  /// adopted into the shared preview slot (used after [syncSessions] appends a
  /// session before the open path marks it preview).
  ///
  /// Shell and run tabs must not be added to the center strip.
  WorkbenchTabId? ensureTab(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
  }) {
    if (!isCenterStripWorkbenchTab(tab.kind)) {
      assert(() {
        debugPrint(
          'WorkbenchCubit.ensureTab: shell/run tabs must not be '
          'added to the center workbench strip',
        );
        return true;
      }());
      return null;
    }
    final bucket = state.bucket(workspaceId);
    final order = List<WorkbenchTabId>.from(bucket.tabOrder);
    final previews = Set<WorkbenchTabId>.from(bucket.previewTabIds);

    final existing = order.indexOf(tab);
    if (existing >= 0) {
      if (!preview) {
        previews.remove(tab);
        emit(
          state.withBucket(
            workspaceId,
            bucket.copyWith(
              tabOrder: order,
              activeTabId: tab,
              previewTabIds: previews,
              welcomeActive: false,
            ),
          ),
        );
        return null;
      }
      if (previews.contains(tab)) {
        emit(
          state.withBucket(
            workspaceId,
            bucket.copyWith(
              tabOrder: order,
              activeTabId: tab,
              previewTabIds: previews,
              welcomeActive: false,
            ),
          ),
        );
        return null;
      }
      // Exists but not preview — drop and re-insert into the preview slot.
      order.removeAt(existing);
    }

    WorkbenchTabId? replaced;
    if (preview) {
      for (final candidate in order) {
        if (previews.contains(candidate)) {
          replaced = candidate;
          break;
        }
      }
    }

    if (replaced != null) {
      final i = order.indexOf(replaced);
      order[i] = tab;
      previews.remove(replaced);
      previews.add(tab);
    } else {
      order.add(tab);
      if (preview) previews.add(tab);
    }

    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(
          tabOrder: order,
          activeTabId: tab,
          previewTabIds: previews,
          welcomeActive: false,
        ),
      ),
    );
    return replaced;
  }

  void pinTab(String workspaceId, WorkbenchTabId tab) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.previewTabIds.contains(tab)) return;
    final previews = Set<WorkbenchTabId>.from(bucket.previewTabIds)
      ..remove(tab);
    emit(
      state.withBucket(workspaceId, bucket.copyWith(previewTabIds: previews)),
    );
  }

  void select(String workspaceId, WorkbenchTabId tab) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.tabOrder.contains(tab)) return;
    final alreadyActive = bucket.activeTabId == tab;
    final needsShellFocus =
        tab.kind == WorkbenchTabKind.shell &&
        bucket.lastFocusedShellTabId != tab;
    if (alreadyActive && !needsShellFocus) return;

    if (alreadyActive) {
      // Still record shell focus when ensureTab already activated this tab.
      emit(
        state.withBucket(
          workspaceId,
          bucket.copyWith(lastFocusedShellTabId: tab),
        ),
      );
      return;
    }

    emit(
      state.withBucket(
        workspaceId,
        tab.kind == WorkbenchTabKind.shell
            ? bucket.copyWith(
                activeTabId: tab,
                lastFocusedShellTabId: tab,
                welcomeActive: false,
              )
            : bucket.copyWith(activeTabId: tab, welcomeActive: false),
      ),
    );
  }

  /// Permutes center-strip [tabOrder]. Preserves [activeTabId].
  void reorderTabs(String workspaceId, int oldIndex, int newIndex) {
    final bucket = state.bucket(workspaceId);
    if (bucket.tabOrder.isEmpty) return;
    final order = reorderListItems(bucket.tabOrder, oldIndex, newIndex);
    if (_listEquals(order, bucket.tabOrder)) return;
    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(tabOrder: order),
      ),
    );
  }

  void removeTab(String workspaceId, WorkbenchTabId tab) {
    final bucket = state.bucket(workspaceId);
    final order = List<WorkbenchTabId>.from(bucket.tabOrder);
    final index = order.indexOf(tab);
    if (index < 0) return;
    order.removeAt(index);
    final previews = Set<WorkbenchTabId>.from(bucket.previewTabIds)
      ..remove(tab);

    WorkbenchTabId? nextActive = bucket.activeTabId;
    if (bucket.activeTabId == tab) {
      if (order.isEmpty) {
        nextActive = null;
      } else if (index > 0) {
        nextActive = order[index - 1];
      } else {
        nextActive = order.first;
      }
    }

    emit(
      state.withBucket(
        workspaceId,
        WorkbenchWorkspaceState(
          tabOrder: order,
          activeTabId: nextActive,
          previewTabIds: previews,
          lastFocusedShellTabId: bucket.lastFocusedShellTabId,
          welcomeActive: nextActive == null ? bucket.welcomeActive : false,
        ),
      ),
    );
  }

  /// Returns tabs that were removed (domain closers should run on these).
  List<WorkbenchTabId> closeOthers(String workspaceId, WorkbenchTabId keep) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.tabOrder.contains(keep)) return const [];
    final removed = bucket.tabOrder
        .where((t) => t != keep)
        .toList(growable: false);
    final previews = {if (bucket.previewTabIds.contains(keep)) keep};
    emit(
      state.withBucket(
        workspaceId,
        WorkbenchWorkspaceState(
          tabOrder: [keep],
          activeTabId: keep,
          previewTabIds: previews,
          lastFocusedShellTabId: bucket.lastFocusedShellTabId,
          welcomeActive: false,
        ),
      ),
    );
    return removed;
  }

  /// Returns tabs that were removed.
  List<WorkbenchTabId> closeRight(String workspaceId, WorkbenchTabId anchor) {
    final bucket = state.bucket(workspaceId);
    final index = bucket.tabOrder.indexOf(anchor);
    if (index < 0 || index >= bucket.tabOrder.length - 1) {
      return const [];
    }
    final kept = bucket.tabOrder.sublist(0, index + 1);
    final removed = bucket.tabOrder.sublist(index + 1);
    final active = bucket.activeTabId;
    final nextActive = active != null && removed.contains(active)
        ? anchor
        : active;
    final previews = bucket.previewTabIds.where(kept.contains).toSet();
    emit(
      state.withBucket(
        workspaceId,
        WorkbenchWorkspaceState(
          tabOrder: kept,
          activeTabId: nextActive,
          previewTabIds: previews,
          lastFocusedShellTabId: bucket.lastFocusedShellTabId,
          welcomeActive: nextActive == null ? bucket.welcomeActive : false,
        ),
      ),
    );
    return removed;
  }

  void clearWorkspace(String workspaceId) {
    if (!state.byWorkspace.containsKey(workspaceId)) return;
    final next = Map<String, WorkbenchWorkspaceState>.from(state.byWorkspace)
      ..remove(workspaceId);
    emit(WorkbenchState(byWorkspace: next));
  }

  /// Keep session tabs in [tabOrder] aligned with [sessionIds] (create/close/hydrate).
  ///
  /// When [newChatActive] is true, [activeTabId] stays null so the body shows
  /// landing while session tabs may still appear in the bar.
  /// When [WorkbenchWorkspaceState.welcomeActive] is true, [activeTabId] stays
  /// null so the welcome page is not replaced by an auto-selected session.
  /// When not in new-chat / welcome mode and active is unset/invalid, activates
  /// [preferredActiveSessionId] (or the first session).
  /// Does not override an active file/diff tab.
  void syncSessions(
    String workspaceId,
    List<String> sessionIds, {
    String? preferredActiveSessionId,
    bool newChatActive = false,
  }) {
    final bucket = state.bucket(workspaceId);
    final sessionSet = sessionIds.toSet();
    final order = <WorkbenchTabId>[];

    for (final tab in bucket.tabOrder) {
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

    var welcomeActive = bucket.welcomeActive;
    WorkbenchTabId? active = bucket.activeTabId;
    if (newChatActive) {
      active = null;
      welcomeActive = false;
    } else if (welcomeActive) {
      active = null;
    } else if (active != null && !order.contains(active)) {
      active = null;
    }

    if (!newChatActive &&
        !welcomeActive &&
        (active == null || active.kind == WorkbenchTabKind.session)) {
      final preferred = preferredActiveSessionId == null
          ? null
          : WorkbenchTabId.session(preferredActiveSessionId);
      if (preferred != null && order.contains(preferred)) {
        active = preferred;
      } else if (active == null) {
        WorkbenchTabId? firstSession;
        for (final t in order) {
          if (t.kind == WorkbenchTabKind.session) {
            firstSession = t;
            break;
          }
        }
        active = firstSession;
      }
    }

    if (_listEquals(order, bucket.tabOrder) &&
        active == bucket.activeTabId &&
        welcomeActive == bucket.welcomeActive) {
      return;
    }

    final previews = bucket.previewTabIds.where(order.contains).toSet();
    emit(
      state.withBucket(
        workspaceId,
        WorkbenchWorkspaceState(
          tabOrder: order,
          activeTabId: active,
          previewTabIds: previews,
          lastFocusedShellTabId: bucket.lastFocusedShellTabId,
          welcomeActive: welcomeActive,
        ),
      ),
    );
  }

  void clearActive(String workspaceId) {
    final bucket = state.bucket(workspaceId);
    if (bucket.activeTabId == null) return;
    emit(state.withBucket(workspaceId, bucket.copyWith(clearActive: true)));
  }

  /// Leave compose / clear selection and hold the welcome empty center.
  ///
  /// Unlike [clearActive], this works when active is already null (compose
  /// path) and blocks [syncSessions] from auto-selecting a session tab.
  void enterWelcome(String workspaceId) {
    final bucket = state.bucket(workspaceId);
    if (bucket.activeTabId == null && bucket.welcomeActive) return;
    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(clearActive: true, welcomeActive: true),
      ),
    );
  }

  static bool _listEquals(List<WorkbenchTabId> a, List<WorkbenchTabId> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
