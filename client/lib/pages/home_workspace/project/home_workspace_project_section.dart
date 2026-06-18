/// Left icon rail sections on the workspace detail page.
enum WorkspaceSection {
  conversations,
  settings,

  /// Personal workspaces only — [WorkspaceConfigPanel] with in-page nav.
  manage,

  /// Sub-sections inside [manage]; not top-level rail entries.
  agent,
  skills,
  plugins,
  mcp,
  extensions,

  /// Team workspaces only — deep-link to team workspace tabs.
  teamConfig,
}

/// Categories inside the workspace settings panel.
enum WorkspaceSettingsSection { basic, danger }
