/// Callback host for the workspace title-bar tab commands (next/prev tab,
/// close active tab, reopen last closed tab).
///
/// [HomeShell] owns the tab list (`_openTabs` / `_recentlyClosed`) and is the
/// only widget that can implement these commands, but the root
/// [ShortcutDispatcher] and the live shortcut context in `main.dart` need to
/// reach them from outside the `HomeShell` subtree (and before it first
/// mounts). This host bridges that gap: [AppShell] owns one long-lived
/// instance (like `CommandBus`); the mounted `HomeShell` assigns real
/// callbacks into it in `initState` and clears it in `dispose`, so callers
/// see `null` callbacks / `openTabCount == 0` whenever no `HomeShell` is
/// mounted.
class WorkspaceChromeCommands {
  /// Selects the next open workspace tab, wrapping from the last tab back
  /// to the first. `null` while no `HomeShell` is mounted.
  void Function()? nextWorkspaceTab;

  /// Selects the previous open workspace tab, wrapping from the first tab
  /// back to the last. `null` while no `HomeShell` is mounted.
  void Function()? prevWorkspaceTab;

  /// Closes the currently active workspace tab. `null` while no `HomeShell`
  /// is mounted.
  void Function()? closeActiveWorkspaceTab;

  /// Reopens the most recently closed workspace tab, if any. `null` while
  /// no `HomeShell` is mounted.
  void Function()? reopenClosedWorkspaceTab;

  /// Number of open workspace title-bar tabs; `0` while no `HomeShell` is
  /// mounted.
  int openTabCount = 0;

  /// Resets to the unmounted state. Called by `HomeShell` on dispose so
  /// stale callbacks bound to a disposed `State` are never invoked.
  void clear() {
    nextWorkspaceTab = null;
    prevWorkspaceTab = null;
    closeActiveWorkspaceTab = null;
    reopenClosedWorkspaceTab = null;
    openTabCount = 0;
  }
}
