import '../../l10n/app_localizations.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../home_workspace/workspace/config/workspace_cli_config_helpers.dart';

/// Catalog CLI for provider/model pickers when member uses **custom** config.
/// Requires [member.cli] on mixed teams (no team fallback).
CliTool memberCustomCatalogCli(TeamProfile team, TeamMemberConfig member) {
  if (team.teamMode == TeamMode.mixed) {
    return member.cli ?? team.cli;
  }
  return team.cli;
}

bool memberLaunchIsConfigured({
  required TeamProfile team,
  required TeamMemberConfig member,
  required CliToolRegistry registry,
  required List<CliPreset> presets,
  AppProviderConfig? provider,
}) {
  final resolved = resolveMemberLaunch(
    team: team,
    member: member,
    globalPresets: presets,
  );
  if (resolved.mode == MemberLaunchMode.custom &&
      team.teamMode == TeamMode.mixed &&
      member.cli == null) {
    return false;
  }
  if (resolved.provider.trim().isEmpty) return false;
  return workspaceCliHidesModelPicker(registry, resolved.cli, provider) ||
      resolved.model.trim().isNotEmpty;
}

String memberLaunchConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required TeamProfile team,
  required TeamMemberConfig member,
  required bool configured,
  required List<CliPreset> presets,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
}) {
  final typeLabel = memberLaunchConfigTypeLabel(
    l10n: l10n,
    team: team,
    member: member,
    presets: presets,
  );
  final configPart = _rawConfigLine(
    l10n: l10n,
    registry: registry,
    team: team,
    member: member,
    configured: configured,
    provider: provider,
    hidesModelPicker: hidesModelPicker,
    presets: presets,
  );
  return '$typeLabel · $configPart';
}

/// Config-type label for summary rows (matches configure-dialog type picker).
String memberLaunchConfigTypeLabel({
  required AppLocalizations l10n,
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> presets,
}) {
  if (member.inheritsTeamPreset) {
    final bundle = resolveTeamLaunchBundle(
      team: team,
      globalPresets: presets,
    );
    if (bundle.isConfigured) {
      return l10n.memberPresetInheritTeam;
    }
    return l10n.memberPresetInheritTeamNone;
  }
  if (member.hasExplicitPreset) {
    return l10n.memberLaunchConfigTypePreset;
  }
  return l10n.memberPresetCustom;
}

String _rawConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required TeamProfile team,
  required TeamMemberConfig member,
  required bool configured,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
  required List<CliPreset> presets,
}) {
  if (!configured) return l10n.workspaceCliNotConfiguredHint;

  final resolved = resolveMemberLaunch(
    team: team,
    member: member,
    globalPresets: presets,
  );
  final def = registry.tryGet(resolved.cli);
  final cliLabel =
      def == null ? resolved.cli.value : cliDisplayName(def, l10n);

  final providerName = provider?.name.trim() ?? resolved.provider.trim();
  final modelLabel = resolved.model.trim();
  final effortLabel = resolved.effort.trim();

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
