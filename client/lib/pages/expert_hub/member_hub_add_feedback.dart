import '../../l10n/app_localizations.dart';
import '../../services/expert_hub/member_roster_service.dart';

/// User-facing toast copy after an Expert Hub add-to-team attempt.
String memberHubAddToastMessage(
  AppLocalizations l10n, {
  required String memberName,
  required MemberAddResult result,
}) {
  final skillCount = result.installedSkillIds.length;
  if (!result.hasFailures) {
    if (skillCount == 0) {
      return l10n.expert.hubAddSuccess(name: memberName);
    }
    return l10n.expert.hubAddSuccessWithSkills(
      name: memberName,
      skillCount: skillCount,
    );
  }
  final failedNames = result.failedDeps.map((f) => f.name).join(', ');
  return l10n.expert.hubAddPartial(
    name: memberName,
    skillCount: skillCount,
    failedCount: result.failedDeps.length,
    failedNames: failedNames,
  );
}

bool memberHubAddToastIsWarning(MemberAddResult result) => result.hasFailures;
