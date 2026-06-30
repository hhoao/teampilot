import '../../l10n/app_localizations.dart';
import '../../services/team/team_clone_service.dart';

/// User-facing toast copy after a TeamHub clone attempt.
String teamHubCloneToastMessage(
  AppLocalizations l10n, {
  required String teamName,
  required CloneResult result,
}) {
  final installed = result.installed;
  if (!result.hasFailures) {
    if (installed.isEmpty) {
      return l10n.teamHubCloneSuccess(teamName);
    }
    return l10n.teamHubCloneSuccessWithDeps(
      teamName,
      installed.skillCount,
      installed.pluginCount,
      installed.mcpCount,
    );
  }
  final failedNames = result.failedDeps.map((f) => f.name).join(', ');
  return l10n.teamHubClonePartial(
    teamName,
    installed.skillCount,
    installed.pluginCount,
    installed.mcpCount,
    result.failedDeps.length,
    failedNames,
  );
}

bool teamHubCloneToastIsWarning(CloneResult result) => result.hasFailures;
