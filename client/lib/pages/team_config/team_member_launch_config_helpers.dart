import '../../l10n/app_localizations.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../home_workspace/project/config/project_cli_config_helpers.dart';

/// Catalog CLI used for provider/model pickers (member override → team default).
CliTool memberCatalogCliFor(TeamConfig team, TeamMemberConfig member) {
  return member.cliWithin(team);
}

bool memberLaunchIsConfigured({
  required TeamMemberConfig member,
  required CliToolRegistry registry,
  required CliTool catalogCli,
  AppProviderConfig? provider,
}) {
  if (member.provider.trim().isEmpty) return false;
  return projectCliHidesModelPicker(registry, catalogCli, provider) ||
      member.model.trim().isNotEmpty;
}

String memberLaunchConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required TeamConfig team,
  required TeamMemberConfig member,
  required bool configured,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
}) {
  if (!configured) return l10n.projectCliNotConfiguredHint;

  final catalogCli = memberCatalogCliFor(team, member);
  final def = registry.tryGet(catalogCli);
  var cliLabel = def == null ? catalogCli.value : cliDisplayName(def, l10n);
  if (team.teamMode == TeamMode.mixed && member.cli == null) {
    cliLabel = '$cliLabel · ${l10n.memberCliInheritHint}';
  }

  final providerName = provider?.name.trim() ?? '';
  final modelLabel = member.model.trim();
  final effortLabel = member.effort.trim();

  if (providerName.isEmpty) return cliLabel;
  if (modelLabel.isEmpty && hidesModelPicker) {
    if (effortLabel.isEmpty) return '$cliLabel · $providerName';
    return '$cliLabel · $providerName · $effortLabel';
  }
  if (modelLabel.isEmpty) {
    if (effortLabel.isEmpty) return '$cliLabel · $providerName';
    return '$cliLabel · $providerName · $effortLabel';
  }
  if (effortLabel.isEmpty) {
    return l10n.aiFeatureConfigSummary(cliLabel, providerName, modelLabel);
  }
  return '${l10n.aiFeatureConfigSummary(cliLabel, providerName, modelLabel)} · $effortLabel';
}
