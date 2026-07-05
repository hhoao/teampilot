import '../../l10n/app_localizations.dart';
import '../../services/expert_hub/member_clone_service.dart';

/// User-facing toast copy after an Expert Hub add-to-team attempt.
String memberHubAddToastMessage(
  AppLocalizations l10n, {
  required String memberName,
  required MemberAddResult result,
}) {
  final skillCount = result.installedSkillIds.length;
  if (!result.hasFailures) {
    if (skillCount == 0) {
      return l10n.expertHubAddSuccess(memberName);
    }
    return l10n.expertHubAddSuccessWithSkills(memberName, skillCount);
  }
  final failedNames = result.failedDeps.map((f) => f.name).join(', ');
  return l10n.expertHubAddPartial(
    memberName,
    skillCount,
    result.failedDeps.length,
    failedNames,
  );
}

bool memberHubAddToastIsWarning(MemberAddResult result) => result.hasFailures;
