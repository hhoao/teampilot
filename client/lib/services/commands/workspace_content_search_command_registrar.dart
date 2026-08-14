import 'command_bus.dart';
import 'command_ids.dart';

/// Holds the content-search panel opener for keyboard shortcuts.
class WorkspaceContentSearchHost {
  void Function()? _openSearch;

  void bind(void Function() openSearch) => _openSearch = openSearch;

  void unbind(void Function() openSearch) {
    if (identical(_openSearch, openSearch)) _openSearch = null;
  }

  void clear() => _openSearch = null;

  void open() => _openSearch?.call();
}

/// Wires [CommandIds.workspaceContentSearch] onto [bus] against [host].
///
/// Call once during app bootstrap (see `buildAppShell`).
void registerWorkspaceContentSearchCommands(
  CommandBus bus,
  WorkspaceContentSearchHost host,
) {
  bus.register(CommandIds.workspaceContentSearch, () => host.open());
}
