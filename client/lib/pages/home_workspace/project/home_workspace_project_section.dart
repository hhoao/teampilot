/// Left icon rail sections on the project detail page.
enum HomeWorkspaceProjectSection {
  conversations,
  settings,

  /// Personal projects only — [HomeWorkspaceProjectConfigWorkspace] with in-page nav.
  manage,

  /// Sub-sections inside [manage]; not top-level rail entries.
  agent,
  skills,
  plugins,
  mcp,
  extensions,

  /// Team projects only — deep-link to team workspace tabs.
  teamConfig,
}

/// Categories inside the project settings panel.
enum ProjectSettingsSection { basic, danger }
