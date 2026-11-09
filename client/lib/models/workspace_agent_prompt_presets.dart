import '../l10n/app_localizations.dart';

/// Built-in role prompts for the personal-workspace agent prompt field.
class WorkspaceAgentPromptPreset {
  const WorkspaceAgentPromptPreset(this.id);

  final String id;

  static const all = <WorkspaceAgentPromptPreset>[
    WorkspaceAgentPromptPreset('general'),
    WorkspaceAgentPromptPreset('developer'),
    WorkspaceAgentPromptPreset('reviewer'),
    WorkspaceAgentPromptPreset('researcher'),
  ];
}

String workspaceAgentPromptPresetLabel(AppLocalizations l10n, String id) {
  return switch (id) {
    'general' => l10n.workspace.agentPromptPresetGeneral,
    'developer' => l10n.workspace.agentPromptPresetDeveloper,
    'reviewer' => l10n.workspace.agentPromptPresetReviewer,
    'researcher' => l10n.workspace.agentPromptPresetResearcher,
    _ => id,
  };
}

String workspaceAgentPromptPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'general' => l10n.workspace.agentPromptPresetGeneralText,
    'developer' => l10n.workspace.agentPromptPresetDeveloperText,
    'reviewer' => l10n.workspace.agentPromptPresetReviewerText,
    'researcher' => l10n.workspace.agentPromptPresetResearcherText,
    _ => '',
  };
}
