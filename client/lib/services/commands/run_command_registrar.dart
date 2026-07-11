import 'dart:async';

import '../../cubits/run_cubit.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Holds the foreground workspace [RunCubit] for keyboard run commands.
///
/// Kept-alive workspace tabs bind/unbind via [RunCommandBinder] when their
/// [WorkspaceRouteActiveScope] becomes active/inactive.
class RunCommandHost {
  RunCubit? _cubit;

  void bind(RunCubit cubit) => _cubit = cubit;

  void unbind(RunCubit cubit) {
    if (identical(_cubit, cubit)) _cubit = null;
  }

  void clear() => _cubit = null;

  Future<void> runSelected() async {
    await _cubit?.runSelected();
  }

  Future<void> stop() async {
    final cubit = _cubit;
    if (cubit == null) return;
    final selected = cubit.state.selectedConfiguration;
    if (selected == null) return;
    final session = cubit.runningSessionFor(selected.selectionKey);
    if (session != null) await cubit.stopSession(session.id);
  }

  Future<void> restart() async {
    final cubit = _cubit;
    if (cubit == null) return;
    final selected = cubit.state.selectedConfiguration;
    if (selected == null) return;
    final session = cubit.runningSessionFor(selected.selectionKey);
    if (session != null) {
      await cubit.restartSession(session.id);
      return;
    }
    await cubit.runSelected();
  }
}

/// Wires run commands onto [bus] against [host].
///
/// Call once during app bootstrap (see `buildAppShell`).
void registerRunCommands(CommandBus bus, RunCommandHost host) {
  bus.register(CommandIds.runRunSelected, () => unawaited(host.runSelected()));
  bus.register(CommandIds.runStop, () => unawaited(host.stop()));
  bus.register(CommandIds.runRestart, () => unawaited(host.restart()));
}
