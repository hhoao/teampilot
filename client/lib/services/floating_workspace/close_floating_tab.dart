import 'package:flutter/material.dart';

import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
import 'floating_surface.dart';
import 'floating_surface_registry.dart';

/// Close pipeline: [FloatingSurface.canClose] → [onTabClosed] → bar close.
///
/// The floating strip ([WorkbenchCubit.bar(workspaceId).floating]) owns
/// presence/order/active; the bar removal also resolves through the domain
/// port (a no-op for shell/run/file/diff — teardown happens in [onTabClosed]).
Future<void> closeFloatingTab({
  required WorkbenchCubit workbench,
  required String workspaceId,
  required FloatingSurfaceRegistry registry,
  required WorkbenchTabId id,
  required FloatingTab tab,
  BuildContext? context,
}) async {
  final surface = registry[tab.surfaceId];
  if (surface == null) {
    await workbench.close(workspaceId, id);
    return;
  }
  if (!await surface.canClose(tab, context: context)) return;
  surface.onTabClosed(tab);
  await workbench.close(workspaceId, id);
}

/// Close every floating tab except [keepId], respecting each surface's
/// [canClose]. [order] is snapshotted so removals do not shift iteration.
Future<void> closeOtherFloatingTabs({
  required WorkbenchCubit workbench,
  required String workspaceId,
  required FloatingSurfaceRegistry registry,
  required WorkbenchTabId keepId,
  BuildContext? context,
}) async {
  final order = List<WorkbenchTabId>.of(workbench.floatingOrder(workspaceId));
  for (final id in order) {
    if (id == keepId) continue;
    await closeFloatingTabByBarId(
      workbench: workbench,
      workspaceId: workspaceId,
      registry: registry,
      id: id,
      context: context,
    );
  }
}

/// Close tabs to the right of [fromId] (exclusive), respecting [canClose].
Future<void> closeFloatingTabsToTheRight({
  required WorkbenchCubit workbench,
  required String workspaceId,
  required FloatingSurfaceRegistry registry,
  required WorkbenchTabId fromId,
  BuildContext? context,
}) async {
  final order = workbench.floatingOrder(workspaceId);
  final index = order.indexOf(fromId);
  if (index < 0 || index >= order.length - 1) return;
  final toClose = order.sublist(index + 1);
  for (final id in toClose) {
    await closeFloatingTabByBarId(
      workbench: workbench,
      workspaceId: workspaceId,
      registry: registry,
      id: id,
      context: context,
    );
  }
}

/// Close every floating tab, respecting each surface's [canClose].
Future<void> closeAllFloatingTabs({
  required WorkbenchCubit workbench,
  required String workspaceId,
  required FloatingSurfaceRegistry registry,
  BuildContext? context,
}) async {
  final order = List<WorkbenchTabId>.of(workbench.floatingOrder(workspaceId));
  for (final id in order) {
    await closeFloatingTabByBarId(
      workbench: workbench,
      workspaceId: workspaceId,
      registry: registry,
      id: id,
      context: context,
    );
  }
}

/// Resolves the [FloatingTab] view model for a bar [id] then runs the close
/// pipeline. Falls back to a bare bar close when the surface is unknown.
Future<void> closeFloatingTabByBarId({
  required WorkbenchCubit workbench,
  required String workspaceId,
  required FloatingSurfaceRegistry registry,
  required WorkbenchTabId id,
  BuildContext? context,
}) async {
  final surfaceId = surfaceIdFor(id.kind);
  if (surfaceId == null) {
    await workbench.close(workspaceId, id);
    return;
  }
  final surface = registry[surfaceId];
  if (surface == null) {
    await workbench.close(workspaceId, id);
    return;
  }
  final tab = surface.createTab(workspaceId: workspaceId, payload: id.id);
  await closeFloatingTab(
    workbench: workbench,
    workspaceId: workspaceId,
    registry: registry,
    id: id,
    tab: tab,
    context: context,
  );
}
