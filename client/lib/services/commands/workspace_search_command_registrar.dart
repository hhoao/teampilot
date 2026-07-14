import 'command_bus.dart';
import 'command_ids.dart';

/// Holds the foreground workspace search opener for keyboard shortcuts.
///
/// Kept-alive workspace tabs bind/unbind when their route becomes
/// active/inactive (see [WorkspaceSplitPane]).
class WorkspaceSearchHost {
  void Function()? _openSearch;

  void bind(void Function() openSearch) => _openSearch = openSearch;

  void unbind(void Function() openSearch) {
    if (identical(_openSearch, openSearch)) _openSearch = null;
  }

  void clear() => _openSearch = null;

  void open() => _openSearch?.call();
}

/// Wires [CommandIds.workspaceSearch] onto [bus] against [host].
///
/// Call once during app bootstrap (see `buildAppShell`).
void registerWorkspaceSearchCommands(CommandBus bus, WorkspaceSearchHost host) {
  bus.register(CommandIds.workspaceSearch, () => host.open());
}
