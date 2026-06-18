import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';

CliTool? catalogCliForTeam(BuildContext context, CliTool cli) {
  final registry = CliToolRegistryScope.maybeOf(context);
  if (registry == null) return null;
  return registry.capability<ProviderCatalogCapability>(cli) != null
      ? cli
      : null;
}

bool memberSupportsAgentPreset(BuildContext context, CliTool cli) {
  final registry = CliToolRegistryScope.maybeOf(context);
  if (registry == null) return false;
  return registry.supportsMemberAgentPreset(cli);
}

/// Pure visibility rule for member agent-preset UI (testable without [BuildContext]).
bool computeMemberShowsAgentPreset({
  required TeamIdentity team,
  required TeamMemberConfig member,
  required bool Function(CliTool cli) supportsPreset,
}) {
  if (team.teamMode == TeamMode.mixed) {
    final override = member.cli;
    if (override == null) return false;
    return supportsPreset(override);
  }
  return supportsPreset(member.cliWithin(team));
}

/// Whether the member editor should show the agent-preset row.
///
/// Native teams always use [TeamIdentity.cli]. Mixed teams only show the row
/// after the member explicitly picks a CLI — "inherit team default" is not
/// enough, or users see agent presets while the CLI dropdown still looks empty.
bool memberShowsAgentPresetUi(
  BuildContext context, {
  required TeamIdentity team,
  required TeamMemberConfig member,
}) {
  final registry = CliToolRegistryScope.maybeOf(context);
  if (registry == null) return false;
  return computeMemberShowsAgentPreset(
    team: team,
    member: member,
    supportsPreset: registry.supportsMemberAgentPreset,
  );
}

/// CLI backing [memberShowsAgentPresetUi] when true.
CliTool? memberAgentPresetCli({
  required TeamIdentity team,
  required TeamMemberConfig member,
}) {
  if (team.teamMode == TeamMode.mixed) {
    return member.cli;
  }
  return member.cliWithin(team);
}

String teamCliDisplayLabel(
  BuildContext context,
  AppLocalizations l10n,
  CliTool cli,
) {
  final def = CliToolRegistryScope.maybeOf(context)?.tryGet(cli);
  if (def != null) {
    return cliDisplayName(
      def,
      l10n,
      registry: CliToolRegistryScope.maybeOf(context),
    );
  }
  return cli.value;
}

bool teamShowsEffortPicker(
  BuildContext context, {
  required CliTool cli,
  required EffortPickerPlacement placement,
  String model = '',
}) {
  final registry = CliToolRegistryScope.maybeOf(context);
  if (registry == null) return false;
  final capability = registry.capability<CliEffortCapability>(cli);
  if (capability == null) return false;
  final target = switch (placement) {
    EffortPickerPlacement.team => capability.teamPickerPlacement(),
    EffortPickerPlacement.member => capability.memberPickerPlacement(),
    EffortPickerPlacement.provider => EffortPickerPlacement.hidden,
    EffortPickerPlacement.hidden => EffortPickerPlacement.hidden,
  };
  if (target != placement) return false;
  return capability.isApplicable(model: model);
}

/// Resolves a preset's provider id to a catalog [AppProviderConfig], if present.
AppProviderConfig? providerConfigForPreset({
  required Iterable<AppProviderConfig> providers,
  required CliPreset preset,
}) {
  final id = preset.provider.trim();
  if (id.isEmpty) return null;
  for (final provider in providers) {
    if (provider.id == id) return provider;
  }
  return null;
}

/// Subtitle for preset picker list items (CLI · provider · model · effort).
String presetPickerSubtitle({
  required CliToolRegistry registry,
  required AppLocalizations l10n,
  required CliPreset preset,
  AppProviderConfig? provider,
}) {
  final def = registry.tryGet(preset.cli);
  final cliName = def != null ? cliDisplayName(def, l10n) : preset.cli.value;
  final providerName = provider?.name.trim().isNotEmpty == true
      ? provider!.name.trim()
      : preset.provider.trim();
  final parts = <String>[
    if (providerName.isNotEmpty) providerName,
    if (preset.model.trim().isNotEmpty) preset.model.trim(),
    if (preset.effort.trim().isNotEmpty) preset.effort.trim(),
  ];
  if (parts.isEmpty) return cliName;
  return '$cliName · ${parts.join(' · ')}';
}

/// Whether team default launch config is set (preset or custom for [catalogCli]).
bool teamLaunchDefaultsConfigured({
  required TeamIdentity team,
  required List<CliPreset> presets,
  required CliTool catalogCli,
}) {
  if (team.activePresetId != null) {
    for (final preset in presets) {
      if (preset.id == team.activePresetId) return true;
    }
    return false;
  }
  return team.hasCustomLaunchDefaultsFor(catalogCli);
}

/// Summary line for team custom defaults (not preset-backed).
String teamCustomLaunchConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required TeamIdentity team,
  required CliTool catalogCli,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
}) {
  final def = registry.tryGet(catalogCli);
  final cliLabel = def == null ? catalogCli.value : cliDisplayName(def, l10n);
  final providerName = provider?.name.trim() ?? team.providerForCli(catalogCli);
  final modelLabel = team.modelForCli(catalogCli);
  final effortLabel = team.effortForCli(catalogCli);

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

/// Summary line for the team default preset row (CLI · provider · model · effort).
String teamPresetConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required CliPreset preset,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
}) {
  final def = registry.tryGet(preset.cli);
  final cliLabel = def == null ? preset.cli.value : cliDisplayName(def, l10n);
  final providerName = provider?.name.trim() ?? preset.provider.trim();
  final modelLabel = preset.model.trim();
  final effortLabel = preset.effort.trim();

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

String memberAgentDropdownItemLabel(
  BuildContext context,
  AppLocalizations l10n,
  String value, {
  List<String> userAgentIds = const [],
}) {
  if (value == FlashskyaiAgentCatalog.noneDropdownValue) {
    return l10n.agentBuiltInNone;
  }
  if (value == FlashskyaiAgentCatalog.customDropdownValue) {
    return l10n.agentBuiltInCustom;
  }
  final ent = FlashskyaiAgentCatalog.tryParseBuiltinId(value);
  if (ent != null) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final hint = zh ? ent.modelHintZh : ent.modelHintEn;
    return '${ent.id} · $hint';
  }
  if (userAgentIds.contains(value)) {
    return value;
  }
  return value;
}
