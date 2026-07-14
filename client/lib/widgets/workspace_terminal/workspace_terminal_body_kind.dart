/// What the workspace Terminal tab renders for the body area.
enum WorkspaceTerminalBodyKind {
  /// No workspace cwd yet — cannot spawn a shell.
  noWorkingDirectory,

  /// Cwd is ready but no session exists — Orca-style launcher (no PTY yet).
  emptyLauncher,

  /// An active terminal entry is selected.
  activeSession,
}

/// Chooses the Terminal body without side effects.
///
/// Lazy start (option B): never implies auto-spawning a PTY — the empty
/// launcher waits for an explicit "New terminal" action.
WorkspaceTerminalBodyKind resolveWorkspaceTerminalBodyKind({
  required String workingDirectory,
  required bool hasActiveEntry,
}) {
  if (workingDirectory.trim().isEmpty) {
    return WorkspaceTerminalBodyKind.noWorkingDirectory;
  }
  if (!hasActiveEntry) return WorkspaceTerminalBodyKind.emptyLauncher;
  return WorkspaceTerminalBodyKind.activeSession;
}
