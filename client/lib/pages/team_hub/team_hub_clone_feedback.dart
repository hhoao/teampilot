import '../../l10n/app_localizations.dart';
import '../../services/team_config/team_clone_service.dart';

/// User-facing toast copy after a TeamHub clone attempt.
String teamHubCloneToastMessage(
  AppLocalizations l10n, {
  required String teamName,
  required CloneResult result,
}) {
  final installed = result.installed;
  if (!result.hasFailures) {
    if (installed.isEmpty) {
      return l10n.teamHub.cloneSuccess(name: teamName);
    }
    return l10n.teamHub.cloneSuccessWithDeps(
      name: teamName,
      skillCount: installed.skillCount,
      pluginCount: installed.pluginCount,
      mcpCount: installed.mcpCount,
      expertCount: installed.expertCount,
    );
  }
  final failedNames = result.failedDeps.map((f) => f.name).join(', ');
  return l10n.teamHub.clonePartial(
    name: teamName,
    skillCount: installed.skillCount,
    pluginCount: installed.pluginCount,
    mcpCount: installed.mcpCount,
    expertCount: installed.expertCount,
    failedCount: result.failedDeps.length,
    failedNames: failedNames,
  );
}

bool teamHubCloneToastIsWarning(CloneResult result) => result.hasFailures;
