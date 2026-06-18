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
    'general' => l10n.workspaceAgentPromptPresetGeneral,
    'developer' => l10n.workspaceAgentPromptPresetDeveloper,
    'reviewer' => l10n.workspaceAgentPromptPresetReviewer,
    'researcher' => l10n.workspaceAgentPromptPresetResearcher,
    _ => id,
  };
}

String workspaceAgentPromptPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'general' => l10n.workspaceAgentPromptPresetGeneralText,
    'developer' => l10n.workspaceAgentPromptPresetDeveloperText,
    'reviewer' => l10n.workspaceAgentPromptPresetReviewerText,
    'researcher' => l10n.workspaceAgentPromptPresetResearcherText,
    _ => '',
  };
}
