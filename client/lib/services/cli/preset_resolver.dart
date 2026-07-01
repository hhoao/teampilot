import '../../models/cli_preset.dart';
import '../../models/team_config.dart';

/// Team-level default launch package (preset or custom defaults).
class TeamLaunchBundle {
  const TeamLaunchBundle({
    required this.cli,
    required this.provider,
    required this.model,
    required this.effort,
    this.sourcePreset,
  });

  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final CliPreset? sourcePreset;

  bool get isConfigured => provider.trim().isNotEmpty;
}

enum MemberLaunchMode {
  /// Full team default: CLI, provider, model, effort from [TeamLaunchBundle].
  inheritTeam,

  /// Member-selected global preset.
  memberPreset,

  /// Member-owned provider / model / effort / CLI (mixed); no team fallback.
  custom,
}

/// Resolved launch configuration for one roster member.
class MemberLaunchResolution {
  const MemberLaunchResolution({
    required this.mode,
    required this.cli,
    required this.provider,
    required this.model,
    required this.effort,
    this.sourcePreset,
  });

  final MemberLaunchMode mode;
  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final CliPreset? sourcePreset;

  bool get isConfigured => provider.trim().isNotEmpty;
}

/// Resolves the team's default launch package.
TeamLaunchBundle resolveTeamLaunchBundle({
  required TeamProfile team,
  required List<CliPreset> globalPresets,
}) {
  final presetId = team.activePresetId?.trim();
  if (presetId != null && presetId.isNotEmpty) {
    final preset = _findPreset(presetId, globalPresets);
    if (preset != null) {
      return TeamLaunchBundle(
        cli: preset.cli,
        provider: preset.provider,
        model: preset.model,
        effort: preset.effort,
        sourcePreset: preset,
      );
    }
  }

  final cli = team.cli;
  return TeamLaunchBundle(
    cli: cli,
    provider: team.providerForCli(cli),
    model: team.modelForCli(cli),
    effort: team.effortForCli(cli),
  );
}

/// Resolves member launch config for staging, validation, and PTY spawn.
///
/// - [MemberLaunchMode.inheritTeam]: entire [resolveTeamLaunchBundle].
/// - [MemberLaunchMode.memberPreset]: member's explicit preset.
/// - [MemberLaunchMode.custom]: member flat fields only (mixed requires [TeamMemberConfig.cli]).
MemberLaunchResolution resolveMemberLaunch({
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> globalPresets,
}) {
  if (member.inheritsTeamPreset) {
    final bundle = resolveTeamLaunchBundle(
      team: team,
      globalPresets: globalPresets,
    );
    return MemberLaunchResolution(
      mode: MemberLaunchMode.inheritTeam,
      cli: bundle.cli,
      provider: bundle.provider,
      model: bundle.model,
      effort: bundle.effort,
      sourcePreset: bundle.sourcePreset,
    );
  }

  if (member.hasExplicitPreset) {
    final preset = _findPreset(member.activePresetId!, globalPresets);
    if (preset != null) {
      return MemberLaunchResolution(
        mode: MemberLaunchMode.memberPreset,
        cli: preset.cli,
        provider: preset.provider,
        model: preset.model,
        effort: preset.effort,
        sourcePreset: preset,
      );
    }
  }

  final cli = _customMemberCli(team, member);
  return MemberLaunchResolution(
    mode: MemberLaunchMode.custom,
    cli: cli,
    provider: member.provider.trim(),
    model: member.model.trim(),
    effort: member.effort.trim(),
  );
}

CliTool _customMemberCli(TeamProfile team, TeamMemberConfig member) {
  if (team.teamMode == TeamMode.mixed) {
    return member.cli ?? team.cli;
  }
  return team.cli;
}

/// Applies [resolveMemberLaunch] for config staging and launch.
TeamMemberConfig memberForLaunch({
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> globalPresets,
}) {
  final resolved = resolveMemberLaunch(
    team: team,
    member: member,
    globalPresets: globalPresets,
  );
  return member.copyWith(
    provider: resolved.provider,
    model: resolved.model,
    effort: resolved.effort,
    updateEffort: true,
    cli: team.teamMode == TeamMode.mixed ? resolved.cli : null,
    updateCli: team.teamMode == TeamMode.mixed,
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
        memberForLaunch(
          team: team,
          member: member,
          globalPresets: globalPresets,
        )
      else
        member,
  ];
}

/// Launch CLI for [member] (single entry point for spawn / adapters).
CliTool memberLaunchCli({
  required TeamProfile team,
  required TeamMemberConfig member,
  required List<CliPreset> globalPresets,
}) {
  return resolveMemberLaunch(
    team: team,
    member: member,
    globalPresets: globalPresets,
  ).cli;
}

/// Presets whose [CliPreset.cli] matches [catalogCli].
List<CliPreset> presetsForCli(
  List<CliPreset> allPresets,
  CliTool catalogCli,
) {
  return allPresets
      .where((p) => p.cli == catalogCli)
      .toList(growable: false);
}

/// Presets for a team-level picker; mixed teams filter by [catalogCli].
List<CliPreset> teamPresetPickerItems({
  required TeamProfile team,
  required List<CliPreset> allPresets,
  CliTool? catalogCli,
}) {
  if (team.teamMode == TeamMode.mixed) {
    final cli = catalogCli ?? team.cli;
    return presetsForCli(allPresets, cli);
  }
  return presetsForCli(allPresets, team.cli);
}

/// Launch CLI from a member record staged by [memberForLaunch] (mixed members
/// carry resolved CLI on [TeamMemberConfig.cli]).
CliTool stagedMemberLaunchCli(TeamProfile team, TeamMemberConfig stagedMember) {
  return team.teamMode == TeamMode.mixed
      ? (stagedMember.cli ?? team.cli)
      : team.cli;
}

CliPreset? _findPreset(String id, List<CliPreset> presets) {
  for (final p in presets) {
    if (p.id == id) return p;
  }
  return null;
}
