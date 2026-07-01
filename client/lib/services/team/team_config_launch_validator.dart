import 'package:equatable/equatable.dart';

import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../cli/preset_resolver.dart';

/// What aspect of team config is missing for launch.
enum TeamConfigIssueKind {
  /// Team has no default provider/preset configured.
  teamDefaultProviderMissing,

  /// A member has no provider configured for its launch mode.
  memberProviderMissing,

  /// A member has a non-official provider but no model.
  memberModelMissing,

  /// Custom mixed member has no CLI selected.
  memberCliMissing,
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
/// start a session. Uses [resolveMemberLaunch] per member launch mode.
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

    final teamBundle = resolveTeamLaunchBundle(
      team: team,
      globalPresets: globalPresets,
    );
    final hasTeamDefault = teamBundle.isConfigured;

    if (members.isEmpty && !hasTeamDefault) {
      issues.add(
        const TeamConfigIssue(TeamConfigIssueKind.teamDefaultProviderMissing),
      );
    }

    for (final member in members) {
      final resolved = resolveMemberLaunch(
        team: team,
        member: member,
        globalPresets: globalPresets,
      );
      if (resolved.mode == MemberLaunchMode.custom &&
          team.teamMode == TeamMode.mixed &&
          member.cli == null) {
        issues.add(_memberIssue(TeamConfigIssueKind.memberCliMissing, member));
        continue;
      }
      if (resolved.provider.trim().isEmpty) {
        issues.add(
          _memberIssue(TeamConfigIssueKind.memberProviderMissing, member),
        );
        continue;
      }
      if (await _needsModel(
        resolved.cli,
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
          (issue) =>
              issue.kind == TeamConfigIssueKind.memberProviderMissing ||
              issue.kind == TeamConfigIssueKind.memberCliMissing,
        );
    if (allMembersMissingProvider && !hasTeamDefault) {
      issues.insert(
        0,
        const TeamConfigIssue(TeamConfigIssueKind.teamDefaultProviderMissing),
      );
    }

    return TeamConfigValidation(
      teamId: team.id,
      mode: team.teamMode,
      teamName: team.name,
      issues: issues,
    );
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
