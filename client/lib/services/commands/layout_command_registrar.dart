import '../../cubits/layout_cubit.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires the v1 zoom + pane-visibility commands onto [bus] against [layout].
///
/// Call once during app bootstrap, after both are constructed (see
/// `buildAppShell`); handlers stay registered for the app's lifetime, so
/// there is no matching unregister step.
void registerLayoutCommands(
  CommandBus bus,
  LayoutCubit layout, {
  required double Function() uiZoomBaseline,
}) {
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
  bus.register(CommandIds.togglePanel, () => layout.toggleWorkspaceTerminal());
  bus.register(
    CommandIds.toggleSecondarySidebar,
    () => layout.toggleRightTools(),
  );
}
