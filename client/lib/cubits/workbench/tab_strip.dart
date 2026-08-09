// lib/cubits/workbench/tab_strip.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'workbench_tab.dart';

/// One strip's entire state: ordered tabs, active tab, preview set.
///
/// The single owner of presence / order / active for one tab surface. Domain
/// runtimes (sessions, files, shells) are referenced by [WorkbenchTabId]; the
/// strip never holds payloads.
@immutable
class TabStrip extends Equatable {
  const TabStrip({
    this.order = const [],
    this.activeId,
    this.previewIds = const {},
  });

  final List<WorkbenchTabId> order;
  final WorkbenchTabId? activeId;

  /// Tabs that are still preview (replaceable) until pinned.
  final Set<WorkbenchTabId> previewIds;

  /// Landing / welcome shows when nothing is selected. Tabs may remain in the
  /// bar (open sessions) while the landing is displayed.
  bool get landingActive => activeId == null;

  bool contains(WorkbenchTabId id) => order.contains(id);

  int indexOf(WorkbenchTabId id) => order.indexOf(id);

  @override
  List<Object?> get props => [order, activeId, previewIds];
}

/// Pure reducer: returns the next [TabStrip] for each mutation. Never mutates
/// in place. Removing an id never resurrects it — re-add requires an explicit
/// [add].
class TabStripReducer {
  const TabStripReducer();

  /// Adds [tab]. When already present and [preview] is false, it is pinned and
  /// activated. When [preview] is true and another preview exists, that preview
  /// is replaced in place and returned. Otherwise the tab is appended at the
  /// end (new tabs surface last).
  (TabStrip, WorkbenchTabId?) add(
    TabStrip strip,
    WorkbenchTabId tab, {
    required bool preview,
    bool activate = true,
  }) {
    final order = List<WorkbenchTabId>.of(strip.order);
    final previews = Set<WorkbenchTabId>.of(strip.previewIds);

    final existing = order.indexOf(tab);
    if (existing >= 0) {
      if (!preview) {
        previews.remove(tab);
        return (
          TabStrip(
            order: order,
            activeId: activate ? tab : strip.activeId,
            previewIds: previews,
          ),
          null,
        );
      }
      if (previews.contains(tab)) {
        return (
          TabStrip(
            order: order,
            activeId: activate ? tab : strip.activeId,
            previewIds: previews,
          ),
          null,
        );
      }
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

    return (
      TabStrip(
        order: order,
        activeId: activate ? tab : strip.activeId,
        previewIds: previews,
      ),
      replaced,
    );
  }

  /// Removes [id]; recomputes active (previous neighbor → first → null).
  /// Returns null when [id] is absent.
  TabStrip? remove(TabStrip strip, WorkbenchTabId id) {
    final order = List<WorkbenchTabId>.of(strip.order);
    final index = order.indexOf(id);
    if (index < 0) return null;

    order.removeAt(index);
    final previews = Set<WorkbenchTabId>.of(strip.previewIds)..remove(id);

    WorkbenchTabId? active = strip.activeId;
    if (active == id) {
      if (order.isEmpty) {
        active = null;
      } else if (index > 0) {
        active = order[index - 1];
      } else {
        active = order.first;
      }
    }
    return TabStrip(order: order, activeId: active, previewIds: previews);
  }

  TabStrip reorder(TabStrip strip, int oldIndex, int newIndex) {
    if (strip.order.isEmpty) return strip;
    if (oldIndex < 0 ||
        oldIndex >= strip.order.length ||
        newIndex < 0 ||
        newIndex >= strip.order.length ||
        oldIndex == newIndex) {
      return strip;
    }
    final order = List<WorkbenchTabId>.of(strip.order);
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    return TabStrip(
      order: order,
      activeId: strip.activeId,
      previewIds: strip.previewIds,
    );
  }

  TabStrip activate(TabStrip strip, WorkbenchTabId id) {
    if (!strip.order.contains(id)) return strip;
    return TabStrip(
      order: strip.order,
      activeId: id,
      previewIds: strip.previewIds,
    );
  }

  TabStrip pin(TabStrip strip, WorkbenchTabId id) {
    if (!strip.previewIds.contains(id)) return strip;
    final previews = Set<WorkbenchTabId>.of(strip.previewIds)..remove(id);
    return TabStrip(
      order: strip.order,
      activeId: strip.activeId,
      previewIds: previews,
    );
  }

  TabStrip enterLanding(TabStrip strip) => TabStrip(
    order: strip.order,
    activeId: null,
    previewIds: strip.previewIds,
  );
}
