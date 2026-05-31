import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import '../utils/team_member_naming.dart';
import 'team_config.dart';
import 'team_member_prompt_presets.dart';

/// Default members and role prompts for a newly created team.
abstract final class DefaultTeamRoster {
  static const developerMemberId = 'developer';
  static const reviewerMemberId = 'reviewer';

  static List<TeamMemberConfig> localized(
    AppLocalizations l10n, {
    int? joinedAt,
  }) {
    return _build(
      joinedAt: joinedAt,
      teamLeadPrompt: teamMemberPromptPresetText(l10n, 'team_lead'),
      developerPrompt: teamMemberPromptPresetText(l10n, 'developer'),
      reviewerPrompt: teamMemberPromptPresetText(l10n, 'reviewer'),
      developerName: l10n.memberPromptPresetDeveloper,
      reviewerName: l10n.memberPromptPresetReviewer,
    );
  }

  /// English prompts when no [AppLocalizations] is available (bootstrap/tests).
  static List<TeamMemberConfig> bootstrap({int? joinedAt}) =>
      localized(AppLocalizationsEn(), joinedAt: joinedAt);

  static List<TeamMemberConfig> _build({
    required String teamLeadPrompt,
    required String developerPrompt,
    required String reviewerPrompt,
    required String developerName,
    required String reviewerName,
    int? joinedAt,
  }) {
    final ts = joinedAt ?? DateTime.now().millisecondsSinceEpoch;
    return [
      TeamMemberConfig(
        id: TeamMemberNaming.teamLeadName,
        name: TeamMemberNaming.teamLeadName,
        prompt: teamLeadPrompt,
        joinedAt: ts,
      ),
      TeamMemberConfig(
        id: developerMemberId,
        name: developerName,
        prompt: developerPrompt,
        joinedAt: ts,
      ),
      TeamMemberConfig(
        id: reviewerMemberId,
        name: reviewerName,
        prompt: reviewerPrompt,
        joinedAt: ts,
      ),
    ];
  }
}
