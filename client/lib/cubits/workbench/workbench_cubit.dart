import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'workbench_tab.dart';

class WorkbenchWorkspaceState extends Equatable {
  const WorkbenchWorkspaceState({
    this.tabOrder = const [],
    this.activeTabId,
    this.previewTabIds = const {},
  });

  final List<WorkbenchTabId> tabOrder;
  final WorkbenchTabId? activeTabId;

  /// Tabs that are still preview (replaceable) until pinned.
  ///
  /// Shared across session / file / diff — at most one preview slot.
  final Set<WorkbenchTabId> previewTabIds;

  bool isPreview(WorkbenchTabId tab) => previewTabIds.contains(tab);

  WorkbenchWorkspaceState copyWith({
    List<WorkbenchTabId>? tabOrder,
    WorkbenchTabId? activeTabId,
    Set<WorkbenchTabId>? previewTabIds,
    bool clearActive = false,
  }) {
    return WorkbenchWorkspaceState(
      tabOrder: tabOrder ?? this.tabOrder,
      activeTabId: clearActive ? null : (activeTabId ?? this.activeTabId),
      previewTabIds: previewTabIds ?? this.previewTabIds,
    );
  }

  @override
  List<Object?> get props => [tabOrder, activeTabId, previewTabIds];
}

class WorkbenchState extends Equatable {
  const WorkbenchState({this.byWorkspace = const {}});

  final Map<String, WorkbenchWorkspaceState> byWorkspace;

  WorkbenchWorkspaceState bucket(String workspaceId) =>
      byWorkspace[workspaceId] ?? const WorkbenchWorkspaceState();

  WorkbenchState withBucket(String workspaceId, WorkbenchWorkspaceState bucket) {
    return WorkbenchState(
      byWorkspace: {...byWorkspace, workspaceId: bucket},
    );
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

  bool isPreview(String workspaceId, WorkbenchTabId tab) =>
      state.bucket(workspaceId).isPreview(tab);

  /// Ensures [tab] is in the bar and active.
  ///
  /// When [preview] is true and another preview exists (any kind), that preview
  /// is replaced in-place and returned so callers can close its domain state.
  /// When [preview] is false, the tab is permanent (pinned).
  ///
  /// If [tab] already exists as a permanent tab and [preview] is true, it is
  /// adopted into the shared preview slot (used after [syncSessions] appends a
  /// session before the open path marks it preview).
  WorkbenchTabId? ensureTab(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
  }) {
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
        ),
      ),
    );
    return replaced;
  }

  void pinTab(String workspaceId, WorkbenchTabId tab) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.previewTabIds.contains(tab)) return;
    final previews = Set<WorkbenchTabId>.from(bucket.previewTabIds)..remove(tab);
    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(previewTabIds: previews),
      ),
    );
  }

  void select(String workspaceId, WorkbenchTabId tab) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.tabOrder.contains(tab)) return;
    if (bucket.activeTabId == tab) return;
    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(activeTabId: tab),
      ),
    );
  }

  void removeTab(String workspaceId, WorkbenchTabId tab) {
    final bucket = state.bucket(workspaceId);
    final order = List<WorkbenchTabId>.from(bucket.tabOrder);
    final index = order.indexOf(tab);
    if (index < 0) return;
    order.removeAt(index);
    final previews = Set<WorkbenchTabId>.from(bucket.previewTabIds)..remove(tab);

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
        ),
      ),
    );
  }

  /// Returns tabs that were removed (domain closers should run on these).
  List<WorkbenchTabId> closeOthers(String workspaceId, WorkbenchTabId keep) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.tabOrder.contains(keep)) return const [];
    final removed =
        bucket.tabOrder.where((t) => t != keep).toList(growable: false);
    final previews = {
      if (bucket.previewTabIds.contains(keep)) keep,
    };
    emit(
      state.withBucket(
        workspaceId,
        WorkbenchWorkspaceState(
          tabOrder: [keep],
          activeTabId: keep,
          previewTabIds: previews,
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
    final nextActive =
        active != null && removed.contains(active) ? anchor : active;
    final previews = bucket.previewTabIds
        .where(kept.contains)
        .toSet();
    emit(
      state.withBucket(
        workspaceId,
        WorkbenchWorkspaceState(
          tabOrder: kept,
          activeTabId: nextActive,
          previewTabIds: previews,
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
  /// When [composeActive] is true, [activeTabId] stays null so the body shows
  /// landing while session tabs may still appear in the bar.
  /// When not composing and active is unset/invalid, activates
  /// [preferredActiveSessionId] (or the first session).
  /// Does not override an active file/diff tab.
  void syncSessions(
    String workspaceId,
    List<String> sessionIds, {
    String? preferredActiveSessionId,
    bool composeActive = false,
  }) {
    final bucket = state.bucket(workspaceId);
    final sessionSet = sessionIds.toSet();
    final order = <WorkbenchTabId>[];

    for (final tab in bucket.tabOrder) {
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

    WorkbenchTabId? active = bucket.activeTabId;
    if (composeActive) {
      active = null;
    } else if (active != null && !order.contains(active)) {
      active = null;
    }

    if (!composeActive &&
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

    if (_listEquals(order, bucket.tabOrder) && active == bucket.activeTabId) {
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
        ),
      ),
    );
  }

  void clearActive(String workspaceId) {
    final bucket = state.bucket(workspaceId);
    if (bucket.activeTabId == null) return;
    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(clearActive: true),
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
