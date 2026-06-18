import 'package:equatable/equatable.dart';

import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../cli/preset_resolver.dart';

/// What aspect of team config is missing for launch.
enum TeamConfigIssueKind {
  /// Team has no default provider/preset and members don't resolve either.
  teamDefaultProviderMissing,

  /// A member has no provider configured after team defaults are applied.
  memberProviderMissing,

  /// A member has a non-official provider but no model after defaults apply.
  memberModelMissing,
}

/// A single validation finding, optionally scoped to a roster member.
class TeamConfigIssue extends Equatable {
  const TeamConfigIssue(this.kind, {this.memberId, this.memberName});

  final TeamConfigIssueKind kind;
  final String? memberId;
  final String? memberName;

  @override
  List<Object?> get props => [kind, memberId, memberName];
}

/// Outcome of [TeamConfigLaunchValidator.validate]: which team was checked and
/// what (if anything) is missing for a clean launch.
class TeamConfigValidation extends Equatable {
  const TeamConfigValidation({
    required this.teamId,
    required this.teamName,
    required this.mode,
    required this.issues,
  });

  final String teamId;
  final String teamName;
  final TeamMode mode;
  final List<TeamConfigIssue> issues;

  bool get hasIssues => issues.isNotEmpty;

  /// First member referenced by an issue, for deep-linking the config dialog
  /// straight to that member; null when only the team-level default is missing.
  String? get firstMemberId {
    for (final issue in issues) {
      final id = issue.memberId;
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  @override
  List<Object?> get props => [teamId, teamName, mode, issues];
}

/// Resolves whether [providerId] (in [cli]'s catalog) is an official provider.
/// Official providers ship their own model, so model selection is optional.
typedef OfficialProviderResolver =
    Future<bool> Function(CliTool cli, String providerId);

/// Pre-launch check that a team has enough provider/model configuration to
/// start a session. Uses [resolveMemberLaunchConfig] so team defaults can
/// satisfy members with empty flat fields.
class TeamConfigLaunchValidator {
  TeamConfigLaunchValidator({OfficialProviderResolver? isOfficialProvider})
    : _isOfficialProvider = isOfficialProvider ?? _defaultIsOfficialProvider;

  final OfficialProviderResolver _isOfficialProvider;

  Future<TeamConfigValidation> validate(
    TeamProfile team, {
    List<CliPreset> globalPresets = const [],
  }) async {
    final members = team.members
        .where((m) => m.isValid)
        .toList(growable: false);
    final issues = <TeamConfigIssue>[];

    final teamPresetExists = team.activePresetId != null &&
        _presetExists(team.activePresetId!, globalPresets);
    final hasTeamCustomDefault = team.hasCustomLaunchDefaultsFor(team.cli);
    final hasTeamDefault =
        teamPresetExists ||
        hasTeamCustomDefault ||
        (team.providerIdsByTool[team.cli.value] ?? '').trim().isNotEmpty;

    if (members.isEmpty && !hasTeamDefault) {
      issues.add(
        const TeamConfigIssue(TeamConfigIssueKind.teamDefaultProviderMissing),
      );
    }

    for (final member in members) {
      final resolved = resolveMemberLaunchConfig(
        team: team,
        member: member,
        globalPresets: globalPresets,
      );
      final effectiveCli = member.cliWithin(team);
      if (resolved.provider.trim().isEmpty) {
        issues.add(
          _memberIssue(TeamConfigIssueKind.memberProviderMissing, member),
        );
        continue;
      }
      if (await _needsModel(
        effectiveCli,
        resolved.provider,
        resolved.model,
      )) {
        issues.add(
          _memberIssue(TeamConfigIssueKind.memberModelMissing, member),
        );
      }
    }

    final allMembersMissingProvider = members.isNotEmpty &&
        issues.isNotEmpty &&
        issues.every(
          (issue) => issue.kind == TeamConfigIssueKind.memberProviderMissing,
        );
    if (allMembersMissingProvider && !hasTeamDefault) {
      issues.insert(
        0,
        const TeamConfigIssue(TeamConfigIssueKind.teamDefaultProviderMissing),
      );
    }

    return TeamConfigValidation(
      teamId: team.id,
      teamName: team.name,
      mode: team.teamMode,
      issues: issues,
    );
  }

  bool _presetExists(String id, List<CliPreset> presets) {
    for (final preset in presets) {
      if (preset.id == id) return true;
    }
    return false;
  }

  /// A model is required only when a non-official provider is configured but no
  /// model is selected. Official providers bundle their own model.
  Future<bool> _needsModel(CliTool cli, String provider, String model) async {
    if (provider.trim().isEmpty) return false;
    if (model.trim().isNotEmpty) return false;
    return !await _isOfficialProvider(cli, provider);
  }

  TeamConfigIssue _memberIssue(
    TeamConfigIssueKind kind,
    TeamMemberConfig member,
  ) => TeamConfigIssue(kind, memberId: member.id, memberName: member.name);

  static Future<bool> _defaultIsOfficialProvider(
    CliTool cli,
    String providerId,
  ) async {
    final id = providerId.trim();
    if (id.isEmpty) return false;
    final provider = await AppProviderRepository().findById(cli, id);
    if (provider == null) return false;
    return provider.isOfficial ||
        provider.category == AppProviderCategory.official;
  }
}
