import 'dart:async';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../commands/command_bus.dart';
import '../commands/command_ids.dart';

/// Wires floating-workspace commands onto [bus] against [floating].
///
/// Call once during app bootstrap after [FloatingWorkspaceCubit] is
/// constructed (see `buildAppShell`). Handlers stay registered for the app's
/// lifetime.
///
/// [onNewTerminal] / [onOpenFile] are injected so shell/file openers can be
/// wired later (or remain null — handlers still [FloatingWorkspaceCubit.ensureOpen]).
///
/// [CommandIds.togglePanel] stays on the layout registrar and should call the
/// same new-terminal path (ensureOpen + shell create) — it aliases this UX.
void registerFloatingWorkspaceCommands(
  CommandBus bus,
  FloatingWorkspaceCubit floating, {
  Future<void> Function()? onNewTerminal,
  Future<void> Function()? onOpenFile,
}) {
  bus.register(CommandIds.floatingToggle, floating.toggle);
  bus.register(CommandIds.floatingMaximize, () {
    final wasOpen =
        floating.state.visibility == FloatingPanelVisibility.open;
    floating.ensureOpen();
    if (!wasOpen) {
      floating.setMaximized(true);
    } else {
      floating.setMaximized(!floating.state.isMaximized);
    }
  });
  bus.register(CommandIds.floatingMinimize, () => floating.minimize());
  bus.register(CommandIds.floatingNewTerminal, () {
    floating.ensureOpen();
    final handler = onNewTerminal;
    if (handler != null) unawaited(handler());
  });
  bus.register(CommandIds.floatingOpenFile, () {
    floating.ensureOpen();
    final handler = onOpenFile;
    if (handler != null) unawaited(handler());
  });
}
