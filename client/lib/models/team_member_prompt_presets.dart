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

/// Responsibilities text (WHAT the role is) → member.prompt.
String teamMemberPromptPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'team_lead' => l10n.memberPromptPresetTeamLeadText,
    'developer' => l10n.memberPromptPresetDeveloperText,
    'reviewer' => l10n.memberPromptPresetReviewerText,
    'researcher' => l10n.memberPromptPresetResearcherText,
    _ => '',
  };
}

/// Working-method text (HOW the role operates) → member.playbook. Paired with the
/// prompt preset of the same [id]. team_lead has none — its method is injected by
/// the system addendum in [MemberRoleProvision].
String teamMemberPlaybookPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'developer' => l10n.memberPlaybookPresetDeveloperText,
    'reviewer' => l10n.memberPlaybookPresetReviewerText,
    'researcher' => l10n.memberPlaybookPresetResearcherText,
    _ => '',
  };
}
