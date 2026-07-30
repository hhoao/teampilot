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
