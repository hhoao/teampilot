import 'dart:async';

import '../../cubits/layout_cubit.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires the v1 zoom + pane-visibility commands onto [bus] against [layout].
///
/// Call once during app bootstrap, after both are constructed (see
/// `buildAppShell`); handlers stay registered for the app's lifetime, so
/// there is no matching unregister step.
///
/// [onTogglePanel] retargets [CommandIds.togglePanel] to the floating-shell
/// new-terminal UX (ensureOpen + create-or-focus shell). It keeps its
/// existing keybinding and aliases [CommandIds.floatingNewTerminal]; the
/// dedicated floating id ships unbound. No longer toggles bottom-dock
/// visibility.
void registerLayoutCommands(
  CommandBus bus,
  LayoutCubit layout, {
  required double Function() uiZoomBaseline,
  bool Function()? composeLanding,
  Future<void> Function()? onTogglePanel,
}) {
  final isCompose = composeLanding ?? () => false;
  bus.register(
    CommandIds.zoomIn,
    () => layout.zoomIn(baseline: uiZoomBaseline()),
  );
  bus.register(
    CommandIds.zoomOut,
    () => layout.zoomOut(baseline: uiZoomBaseline()),
  );
  bus.register(CommandIds.zoomReset, () => layout.zoomReset());
  bus.register(CommandIds.toggleSidebar, () => layout.toggleSidebar());
  bus.register(CommandIds.togglePanel, () {
    final handler = onTogglePanel;
    if (handler != null) {
      unawaited(handler());
    }
  });
  bus.register(
    CommandIds.toggleSecondarySidebar,
    () => layout.toggleRightTools(composeLanding: isCompose()),
  );
}
