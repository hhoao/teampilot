import '../../l10n/app_localizations.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../home_workspace/project/config/project_cli_config_helpers.dart';

/// Catalog CLI used for provider/model pickers (member override → team default).
CliTool memberCatalogCliFor(TeamConfig team, TeamMemberConfig member) {
  return member.cliWithin(team);
}

bool memberLaunchIsConfigured({
  required TeamConfig team,
  required TeamMemberConfig member,
  required CliToolRegistry registry,
  required CliTool catalogCli,
  AppProviderConfig? provider,
  List<CliPreset> presets = const [],
}) {
  final resolved = resolveMemberLaunchConfig(
    team: team,
    member: member,
    globalPresets: presets,
  );
  if (resolved.provider.trim().isEmpty) return false;
  return projectCliHidesModelPicker(registry, catalogCli, provider) ||
      resolved.model.trim().isNotEmpty;
}

String memberLaunchConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required TeamConfig team,
  required TeamMemberConfig member,
  required bool configured,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
  List<CliPreset> presets = const [],
}) {
  final presetLine = memberPresetSummaryLine(
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
  if (presetLine != null) return '$presetLine  ·  $configPart';
  return configPart;
}

/// Returns a preset summary label for display, or `null` when the member uses
/// custom config (no preset).
String? memberPresetSummaryLine({
  required AppLocalizations l10n,
  required TeamConfig team,
  required TeamMemberConfig member,
  required List<CliPreset> presets,
}) {
  if (member.hasExplicitPreset) {
    final preset = _findPreset(presets, member.activePresetId!);
    if (preset != null) return l10n.memberPresetViaPreset(preset.name);
    return member.activePresetId;
  }
  if (member.inheritsTeamPreset) {
    if (team.activePresetId != null) {
      final preset = _findPreset(presets, team.activePresetId!);
      if (preset != null) {
        return l10n.memberPresetViaTeamDefault(preset.name);
      }
    }
    if (team.hasCustomLaunchDefaultsFor(member.cliWithin(team))) {
      return l10n.memberPresetInheritTeam;
    }
    return l10n.memberPresetInheritTeamNone;
  }
  // member.usesCustomConfig — no preset label
  return null;
}

CliPreset? _findPreset(List<CliPreset> presets, String id) {
  for (final p in presets) {
    if (p.id == id) return p;
  }
  return null;
}

String _rawConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required TeamConfig team,
  required TeamMemberConfig member,
  required bool configured,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
  List<CliPreset> presets = const [],
}) {
  if (!configured) return l10n.projectCliNotConfiguredHint;

  final catalogCli = memberCatalogCliFor(team, member);
  final def = registry.tryGet(catalogCli);
  var cliLabel = def == null ? catalogCli.value : cliDisplayName(def, l10n);
  if (team.teamMode == TeamMode.mixed && member.cli == null) {
    cliLabel = '$cliLabel · ${l10n.memberCliInheritHint}';
  }

  final resolved = resolveMemberLaunchConfig(
    team: team,
    member: member,
    globalPresets: presets,
  );
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
