import 'package:flutter/material.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../models/floating_workspace_tab.dart';
import 'floating_surface.dart';
import 'floating_surface_registry.dart';

/// Close pipeline: [FloatingSurface.canClose] → [onTabClosed] → cubit remove.
Future<void> closeFloatingTab({
  required FloatingWorkspaceCubit cubit,
  required FloatingSurfaceRegistry registry,
  required FloatingTab tab,
  BuildContext? context,
}) async {
  final surface = registry[tab.surfaceId];
  if (surface == null) {
    cubit.removeTab(tab.id);
    return;
  }
  if (!await surface.canClose(tab, context: context)) return;
  surface.onTabClosed(tab);
  cubit.removeTab(tab.id);
}

/// Close every tab except [keepTabId], respecting each surface's [canClose].
Future<void> closeOtherFloatingTabs({
  required FloatingWorkspaceCubit cubit,
  required FloatingSurfaceRegistry registry,
  required String keepTabId,
  BuildContext? context,
}) async {
  final toClose = cubit.activeBucket.tabs
      .where((t) => t.id != keepTabId)
      .toList(growable: false);
  for (final tab in toClose) {
    await closeFloatingTab(
      cubit: cubit,
      registry: registry,
      tab: tab,
      context: context,
    );
  }
}

/// Close tabs to the right of [fromTabId] (exclusive), respecting [canClose].
Future<void> closeFloatingTabsToTheRight({
  required FloatingWorkspaceCubit cubit,
  required FloatingSurfaceRegistry registry,
  required String fromTabId,
  BuildContext? context,
}) async {
  final tabs = cubit.activeBucket.tabs;
  final index = tabs.indexWhere((t) => t.id == fromTabId);
  if (index < 0 || index >= tabs.length - 1) return;
  final toClose = tabs.sublist(index + 1);
  for (final tab in toClose) {
    await closeFloatingTab(
      cubit: cubit,
      registry: registry,
      tab: tab,
      context: context,
    );
  }
}
