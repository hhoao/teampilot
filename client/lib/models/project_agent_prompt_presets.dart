import '../l10n/app_localizations.dart';

/// Built-in role prompts for the personal-project agent prompt field.
class ProjectAgentPromptPreset {
  const ProjectAgentPromptPreset(this.id);

  final String id;

  static const all = <ProjectAgentPromptPreset>[
    ProjectAgentPromptPreset('general'),
    ProjectAgentPromptPreset('developer'),
    ProjectAgentPromptPreset('reviewer'),
    ProjectAgentPromptPreset('researcher'),
  ];
}

String projectAgentPromptPresetLabel(AppLocalizations l10n, String id) {
  return switch (id) {
    'general' => l10n.projectAgentPromptPresetGeneral,
    'developer' => l10n.projectAgentPromptPresetDeveloper,
    'reviewer' => l10n.projectAgentPromptPresetReviewer,
    'researcher' => l10n.projectAgentPromptPresetResearcher,
    _ => id,
  };
}

String projectAgentPromptPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'general' => l10n.projectAgentPromptPresetGeneralText,
    'developer' => l10n.projectAgentPromptPresetDeveloperText,
    'reviewer' => l10n.projectAgentPromptPresetReviewerText,
    'researcher' => l10n.projectAgentPromptPresetResearcherText,
    _ => '',
  };
}
