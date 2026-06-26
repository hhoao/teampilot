import '../../models/cli_preset.dart';
import '../../models/team_config.dart';

/// Resolved launch configuration for a team member.
///
/// Returns provider/model/effort resolved from the preset hierarchy:
/// member explicit preset → member inherits team preset (CLI-matched) →
/// member flat fields merged with team custom defaults per effective CLI.
({String provider, String model, String effort, CliPreset? sourcePreset})
resolveMemberLaunchConfig({
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> globalPresets,
}) {
  final effectiveCli = member.cliWithin(team);

  // 1) Member has an explicit preset override.
  if (member.hasExplicitPreset) {
    final preset = _findPreset(member.activePresetId!, globalPresets);
    if (preset != null) {
      return (
        provider: preset.provider,
        model: preset.model,
        effort: preset.effort,
        sourcePreset: preset,
      );
    }
  }

  // 2) Member inherits team preset when CLI matches.
  if (member.inheritsTeamPreset && team.activePresetId != null) {
    final preset = _findPreset(team.activePresetId!, globalPresets);
    if (preset != null && preset.cli == effectiveCli) {
      return (
        provider: preset.provider,
        model: preset.model,
        effort: preset.effort,
        sourcePreset: preset,
      );
    }
  }

  // 3) Member flat fields, with team custom defaults filling gaps.
  var provider = member.provider.trim();
  var model = member.model.trim();
  var effort = member.effort.trim();

  if (provider.isEmpty) {
    provider = team.providerForCli(effectiveCli);
  }
  if (model.isEmpty) {
    model = team.modelForCli(effectiveCli);
  }
  if (effort.isEmpty) {
    effort = team.effortForCli(effectiveCli);
  }

  return (
    provider: provider,
    model: model,
    effort: effort,
    sourcePreset: null,
  );
}

/// Applies [resolveMemberLaunchConfig] to [member] for config staging and launch.
///
/// Preset ids, team per-CLI defaults, and flat member fields collapse into the
/// provider/model/effort fields consumed by config-profile provisioning.
TeamMemberConfig teamMemberWithLaunchConfig({
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> globalPresets,
}) {
  final resolved = resolveMemberLaunchConfig(
    team: team,
    member: member,
    globalPresets: globalPresets,
  );
  return member.copyWith(
    provider: resolved.provider,
    model: resolved.model,
    effort: resolved.effort,
    updateEffort: true,
  );
}

/// Resolves every valid roster member for team launch staging.
List<TeamMemberConfig> resolveTeamRosterForLaunch({
  required TeamProfile team,
  required Iterable<TeamMemberConfig> members,
  required List<CliPreset> globalPresets,
}) {
  return [
    for (final member in members)
      if (member.isValid)
        teamMemberWithLaunchConfig(
          team: team,
          member: member,
          globalPresets: globalPresets,
        )
      else
        member,
  ];
}

/// Presets whose [CliPreset.cli] matches the member's effective CLI.
///
/// Use in member-level preset pickers so only compatible presets are shown.
/// Pass [catalogCli] when the picker reflects a tentative CLI (e.g. mixed-member
/// configure dialog before save).
List<CliPreset> eligiblePresets({
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> allPresets,
  CliTool? catalogCli,
}) {
  final effectiveCli = catalogCli ?? member.cliWithin(team);
  return allPresets.where((p) => p.cli == effectiveCli).toList(growable: false);
}

/// Presets whose [CliPreset.cli] matches [teamCli].
///
/// Use in native team-level preset pickers.
List<CliPreset> teamEligiblePresets({
  required CliTool teamCli,
  required List<CliPreset> allPresets,
}) {
  return allPresets.where((p) => p.cli == teamCli).toList(growable: false);
}

/// Presets for a team-level picker; mixed teams see all presets, native teams
/// are filtered to [team.cli].
List<CliPreset> teamPresetPickerItems({
  required TeamProfile team,
  required List<CliPreset> allPresets,
  CliTool? catalogCli,
}) {
  if (team.teamMode == TeamMode.mixed) {
    final cli = catalogCli ?? team.cli;
    return allPresets.where((p) => p.cli == cli).toList(growable: false);
  }
  return teamEligiblePresets(teamCli: team.cli, allPresets: allPresets);
}

CliPreset? _findPreset(String id, List<CliPreset> presets) {
  for (final p in presets) {
    if (p.id == id) return p;
  }
  return null;
}
