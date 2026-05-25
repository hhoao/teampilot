import '../l10n/app_localizations.dart';

/// Built-in role prompts for the team member prompt field (roster notes).
class TeamMemberPromptPreset {
  const TeamMemberPromptPreset(this.id);

  final String id;

  static const all = <TeamMemberPromptPreset>[
    TeamMemberPromptPreset('team_lead'),
    TeamMemberPromptPreset('developer'),
    TeamMemberPromptPreset('reviewer'),
    TeamMemberPromptPreset('researcher'),
  ];
}

String teamMemberPromptPresetLabel(AppLocalizations l10n, String id) {
  return switch (id) {
    'team_lead' => l10n.memberPromptPresetTeamLead,
    'developer' => l10n.memberPromptPresetDeveloper,
    'reviewer' => l10n.memberPromptPresetReviewer,
    'researcher' => l10n.memberPromptPresetResearcher,
    _ => id,
  };
}

String teamMemberPromptPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'team_lead' => l10n.memberPromptPresetTeamLeadText,
    'developer' => l10n.memberPromptPresetDeveloperText,
    'reviewer' => l10n.memberPromptPresetReviewerText,
    'researcher' => l10n.memberPromptPresetResearcherText,
    _ => '',
  };
}
