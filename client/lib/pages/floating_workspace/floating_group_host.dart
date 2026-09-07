import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/workbench/tab_strip.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
import '../../services/floating_workspace/close_floating_tab.dart';
import '../../services/floating_workspace/floating_surface_registry.dart';
import '../../widgets/workbench/workbench_shell_run_sync.dart';
import '../../widgets/workbench/workbench_split_layout_view.dart';
import '../../widgets/workbench/workbench_tab_drag.dart';
import 'floating_workspace_tab_bar.dart';

/// The panel-facing projection of one floating [TabStrip]: resolved
/// [FloatingTab]s plus the id maps the strip callbacks need.
@immutable
class FloatingStripProjection {
  const FloatingStripProjection({
    required this.tabs,
    required this.activeTabId,
    required this.barIdByTabId,
    required this.previewTabIds,
    required this.pinnedTabIds,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;

  /// Chip tab id ([FloatingTab.id]) → bar-level [WorkbenchTabId].
  final Map<String, WorkbenchTabId> barIdByTabId;
  final Set<String> previewTabIds;
  final Set<String> pinnedTabIds;
}

/// Projects a floating strip through the surface registry
/// ([resolveFloatingTabForId]): bar ids become [FloatingTab]s; ids with no
/// resolvable surface are skipped, so strip callbacks always resolve ids
/// through [FloatingStripProjection.barIdByTabId].
FloatingStripProjection projectFloatingStrip({
  required FloatingSurfaceRegistry registry,
  required String workspaceId,
  required TabStrip strip,
}) {
  final tabs = <FloatingTab>[];
  final barIdByTabId = <String, WorkbenchTabId>{};
  final previewTabIds = <String>{};
  final pinnedTabIds = <String>{};
  String? activeTabId;
  for (final barId in strip.order) {
    final tab = resolveFloatingTabForId(
      registry: registry,
      workspaceId: workspaceId,
      id: barId,
    );
    if (tab == null) continue;
    tabs.add(tab);
    barIdByTabId[tab.id] = barId;
    if (strip.previewIds.contains(barId)) previewTabIds.add(tab.id);
    if (strip.pinnedIds.contains(barId)) pinnedTabIds.add(tab.id);
    if (barId == strip.activeId) activeTabId = tab.id;
  }
  return FloatingStripProjection(
    tabs: tabs,
    activeTabId: activeTabId,
    barIdByTabId: barIdByTabId,
    previewTabIds: previewTabIds,
    pinnedTabIds: pinnedTabIds,
  );
}

/// One floating split group's pane: a slim header strip carrying this group's
/// own tabs ([FloatingWorkspaceTabBar] re-instantiated per group) above the
/// group's tab bodies, wrapped in a focus frame ([SplitGroupFocusFrame]) and a
/// drag drop region ([WorkbenchTabDropRegions], body only — the header stays
/// outside so plain chip clicks never dispatch drops).
///
/// The header is shown only while the floating layout hosts more than one
/// group (single group keeps today's panel chrome: title bar strip only).
/// Split menu entries and chip drags are offered only while [splitEnabled]
/// (the panel is wide/tall enough to host a split).
class FloatingGroupHost extends StatelessWidget {
  const FloatingGroupHost({
    required this.workspaceId,
    required this.groupId,
    required this.strip,
    required this.focused,
    required this.showHeader,
    required this.splitEnabled,
    required this.registry,
    super.key,
  });

  final String workspaceId;
  final String groupId;
  final TabStrip strip;
  final bool focused;

  /// Whether the slim per-group header strip renders (multi-group only).
  final bool showHeader;

  /// Whether split interactions (split menu, tab drags) are available.
  final bool splitEnabled;
  final FloatingSurfaceRegistry registry;

  @override
  Widget build(BuildContext context) {
    final projection = projectFloatingStrip(
      registry: registry,
      workspaceId: workspaceId,
      strip: strip,
    );
    return SplitGroupFocusFrame(
      focused: focused,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            _FloatingGroupHeaderStrip(
              workspaceId: workspaceId,
              groupId: groupId,
              strip: strip,
              splitEnabled: splitEnabled,
              registry: registry,
              projection: projection,
            ),
          Expanded(
            child: WorkbenchTabDropRegions(
              groupId: groupId,
              child: _FloatingTabBodyStack(
                tabs: projection.tabs,
                activeTabId: projection.activeTabId,
                registry: registry,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim per-group tab strip: this group's [FloatingWorkspaceTabBar] instance
/// (compact metrics, no "+" button) with callbacks routed to the owning group
/// — pin/unpin read THIS strip's preview/pin state, bulk closes go through the
/// whole-surface close pipeline, and reorder focuses the group first (the
/// reorder mutates the focused group).
class _FloatingGroupHeaderStrip extends StatelessWidget {
  const _FloatingGroupHeaderStrip({
    required this.workspaceId,
    required this.groupId,
    required this.strip,
    required this.splitEnabled,
    required this.registry,
    required this.projection,
  });

  final String workspaceId;
  final String groupId;
  final TabStrip strip;
  final bool splitEnabled;
  final FloatingSurfaceRegistry registry;
  final FloatingStripProjection projection;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = context.read<WorkbenchCubit>();
    final tabs = projection.tabs;
    // Split entries / chip drags only while the panel can host a split and
    // the group holds more than one tab (a sole tab cannot be split out —
    // reducer no-op).
    final canSplit = splitEnabled && strip.order.length > 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: FloatingWorkspaceTabBar(
            tabs: tabs,
            activeTabId: projection.activeTabId,
            previewTabIds: projection.previewTabIds,
            pinnedTabIds: projection.pinnedTabIds,
            onSelect: (tabId) {
              final barId = projection.barIdByTabId[tabId];
              if (barId != null) {
                workbench.activate(workspaceId, barId);
              }
              final tab = tabs.firstWhereOrNull((t) => t.id == tabId);
              if (tab != null) {
                final surface = registry[tab.surfaceId];
                if (surface != null) {
                  unawaited(surface.activate(tab));
                }
              }
            },
            onClose: (tab) {
              final barId = projection.barIdByTabId[tab.id];
              if (barId == null) return;
              unawaited(
                closeFloatingTab(
                  workbench: workbench,
                  workspaceId: workspaceId,
                  registry: registry,
                  id: barId,
                  tab: tab,
                  context: context,
                ),
              );
            },
            onCloseOthers: (tab) {
              final barId = projection.barIdByTabId[tab.id];
              if (barId == null) return;
              unawaited(
                closeOtherFloatingTabs(
                  workbench: workbench,
                  workspaceId: workspaceId,
                  registry: registry,
                  keepId: barId,
                  context: context,
                ),
              );
            },
            onCloseRight: (tab) {
              final barId = projection.barIdByTabId[tab.id];
              if (barId == null) return;
              unawaited(
                closeFloatingTabsToTheRight(
                  workbench: workbench,
                  workspaceId: workspaceId,
                  registry: registry,
                  fromId: barId,
                  context: context,
                ),
              );
            },
            onCloseAll: () {
              unawaited(
                closeAllFloatingTabs(
                  workbench: workbench,
                  workspaceId: workspaceId,
                  registry: registry,
                  context: context,
                ),
              );
            },
            onReorder: (oldIndex, newIndex) {
              // reorderFloating mutates the focused group — focus this one so
              // the drag acts on the strip it started from.
              workbench.focusGroup(workspaceId, groupId, floating: true);
              workbench.reorderFloating(workspaceId, oldIndex, newIndex);
            },
            onPin: (tabId) {
              final barId = projection.barIdByTabId[tabId];
              if (barId == null) return;
              if (strip.previewIds.contains(barId)) {
                workbench.promote(workspaceId, barId);
              } else {
                workbench.pin(workspaceId, barId);
              }
            },
            onUnpin: (tabId) {
              final barId = projection.barIdByTabId[tabId];
              if (barId == null) return;
              workbench.unpin(workspaceId, barId);
            },
            onDoubleTap: (tabId) {
              final barId = projection.barIdByTabId[tabId];
              if (barId == null) return;
              if (strip.previewIds.contains(barId)) {
                workbench.promote(workspaceId, barId);
              } else if (strip.pinnedIds.contains(barId)) {
                workbench.unpin(workspaceId, barId);
              } else {
                workbench.pin(workspaceId, barId);
              }
            },
            onSplitRight: canSplit
                ? (tabId) => _split(context, tabId, Axis.horizontal)
                : null,
            onSplitDown: canSplit
                ? (tabId) => _split(context, tabId, Axis.vertical)
                : null,
            tabDrag: splitEnabled
                ? FloatingTabStripDrag(
                    sourceGroupId: groupId,
                    resolveTabId: (tabId) => projection.barIdByTabId[tabId],
                    onDrop: (tab, targetGroupId, zone) => dispatchSplitDrop(
                      workbench,
                      workspaceId,
                      tab: tab,
                      sourceGroupId: groupId,
                      targetGroupId: targetGroupId,
                      zone: zone,
                      floating: true,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  void _split(BuildContext context, String tabId, Axis axis) {
    final workbench = context.read<WorkbenchCubit>();
    final barId = projection.barIdByTabId[tabId];
    if (barId == null) return;
    workbench.splitTab(
      workspaceId,
      barId,
      axis: axis,
      before: false,
      floating: true,
    );
  }
}

/// Keeps every tab of this group mounted; inactive tabs skip layout/paint.
/// Mirror of the panel's keep-alive semantics (formerly
/// `_FloatingTabBodyStack` in `floating_workspace_panel.dart`) — one stack per
/// group; a tab lives in exactly one group, so all open tabs stay mounted
/// while every group renders.
class _FloatingTabBodyStack extends StatelessWidget {
  const _FloatingTabBodyStack({
    required this.tabs,
    required this.activeTabId,
    required this.registry,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;
  final FloatingSurfaceRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tab in tabs)
          TpKeepAliveLayer(
            key: ValueKey(tab.id),
            active: tab.id == activeTabId,
            child: ExcludeSemantics(
              excluding: tab.id != activeTabId,
              child: TickerMode(
                enabled: tab.id == activeTabId,
                child: IgnorePointer(
                  ignoring: tab.id != activeTabId,
                  child: TpDeferredForegroundMount(
                    active: tab.id == activeTabId,
                    retainWhenInactive: true,
                    placeholder: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    builder: (context) => _buildTabBody(context, tab),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBody(BuildContext context, FloatingTab tab) {
    final surface = registry[tab.surfaceId];
    if (surface == null) return const SizedBox.shrink();
    return surface.build(context, tab);
  }
}
