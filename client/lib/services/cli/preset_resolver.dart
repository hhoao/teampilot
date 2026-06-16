import '../../models/cli_preset.dart';
import '../../models/team_config.dart';

/// Resolved launch configuration for a team member.
///
/// Returns provider/model/effort resolved from the preset hierarchy:
/// member explicit preset → member inherits team preset → member flat fields.
({String provider, String model, String effort, CliPreset? sourcePreset})
resolveMemberLaunchConfig({
  required TeamConfig team,
  required TeamMemberConfig member,
  required List<CliPreset> globalPresets,
}) {
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

  // 2) Member inherits team default and team has a preset set.
  if (member.inheritsTeamPreset && team.activePresetId != null) {
    final preset = _findPreset(team.activePresetId!, globalPresets);
    if (preset != null) {
      return (
        provider: preset.provider,
        model: preset.model,
        effort: preset.effort,
        sourcePreset: preset,
      );
    }
  }

  // 3) Fall back to member's own flat fields (may be empty strings).
  return (
    provider: member.provider,
    model: member.model,
    effort: member.effort,
    sourcePreset: null,
  );
}

/// Presets whose [CliPreset.cli] matches the member's effective CLI.
///
/// Use in member-level preset pickers so only compatible presets are shown.
List<CliPreset> eligiblePresets({
  required TeamConfig team,
  required TeamMemberConfig member,
  required List<CliPreset> allPresets,
}) {
  final effectiveCli = member.cliWithin(team);
  return allPresets.where((p) => p.cli == effectiveCli).toList(growable: false);
}

/// Presets whose [CliPreset.cli] matches [teamCli].
///
/// Use in team-level preset pickers.
List<CliPreset> teamEligiblePresets({
  required CliTool teamCli,
  required List<CliPreset> allPresets,
}) {
  return allPresets.where((p) => p.cli == teamCli).toList(growable: false);
}

CliPreset? _findPreset(String id, List<CliPreset> presets) {
  for (final p in presets) {
    if (p.id == id) return p;
  }
  return null;
}
