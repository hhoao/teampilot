/// Left icon rail sections on the project detail page.
enum HomeWorkspaceProjectSection {
  conversations,
  settings,

  /// Personal projects only — project-scoped agent / CLI config.
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
