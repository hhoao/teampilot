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
    'team_lead' => l10n.member.promptPresetTeamLead,
    'developer' => l10n.member.promptPresetDeveloper,
    'reviewer' => l10n.member.promptPresetReviewer,
    'researcher' => l10n.member.promptPresetResearcher,
    _ => id,
  };
}

/// Responsibilities text (WHAT the role is) → member.responsibilities.
String teamMemberPromptPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'team_lead' => l10n.member.promptPresetTeamLeadText,
    'developer' => l10n.member.promptPresetDeveloperText,
    'reviewer' => l10n.member.promptPresetReviewerText,
    'researcher' => l10n.member.promptPresetResearcherText,
    _ => '',
  };
}

/// Working-method text (HOW the role operates) → member.playbook. Paired with the
/// prompt preset of the same [id]. team_lead has none — its method is injected by
/// the system addendum in [MemberRoleProvision].
String teamMemberPlaybookPresetText(AppLocalizations l10n, String id) {
  return switch (id) {
    'developer' => l10n.member.playbookPresetDeveloperText,
    'reviewer' => l10n.member.playbookPresetReviewerText,
    'researcher' => l10n.member.playbookPresetResearcherText,
    _ => '',
  };
}
