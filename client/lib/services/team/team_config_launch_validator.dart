import 'package:equatable/equatable.dart';

import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';

/// What aspect of team config is missing for launch.
enum TeamConfigIssueKind {
  /// native: team has no explicit default provider for its CLI, and members
  /// don't supply their own provider either.
  teamDefaultProviderMissing,

  /// A member has no provider configured.
  memberProviderMissing,

  /// A member has a non-official provider but no model selected.
  memberModelMissing,

  /// mixed: a member has no CLI selected (no per-member override).
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

/// Pre-launch check that a team has enough provider/model/CLI configuration to
/// start a session. Provider/model/CLI presence is checked structurally; the
/// model requirement is waived for official providers (which carry their own
/// model) via [OfficialProviderResolver].
///
/// Rules:
/// - **native**: a session uses one CLI ([TeamConfig.cli]). It is satisfied when
///   the team has an explicit default provider for that CLI
///   (`providerIdsByTool[cli]`, strict — global "sole provider" fallback is not
///   counted). Without a team default, every valid member must instead carry
///   their own provider, plus a model unless that provider is official.
/// - **mixed**: each valid member runs its own CLI, so each must have a CLI
///   override and a provider, plus a model unless the provider is official.
class TeamConfigLaunchValidator {
  TeamConfigLaunchValidator({OfficialProviderResolver? isOfficialProvider})
    : _isOfficialProvider = isOfficialProvider ?? _defaultIsOfficialProvider;

  final OfficialProviderResolver _isOfficialProvider;

  Future<TeamConfigValidation> validate(TeamConfig team) async {
    final members = team.members
        .where((m) => m.isValid)
        .toList(growable: false);
    final issues = <TeamConfigIssue>[];

    if (team.teamMode == TeamMode.mixed) {
      for (final member in members) {
        if (member.cli == null) {
          issues.add(
            _memberIssue(TeamConfigIssueKind.memberCliMissing, member),
          );
        }
        if (member.provider.trim().isEmpty) {
          issues.add(
            _memberIssue(TeamConfigIssueKind.memberProviderMissing, member),
          );
        } else if (await _needsModel(
          member.cliWithin(team),
          member.provider,
          member.model,
        )) {
          issues.add(
            _memberIssue(TeamConfigIssueKind.memberModelMissing, member),
          );
        }
      }
    } else {
      final hasTeamDefault = (team.providerIdsByTool[team.cli.value] ?? '')
          .trim()
          .isNotEmpty;
      if (!hasTeamDefault) {
        final anyMemberProvider = members.any(
          (m) => m.provider.trim().isNotEmpty,
        );
        // No team default and nobody supplies a provider → the simplest fix is
        // configuring the team default; surface it as an overarching hint.
        if (members.isEmpty || !anyMemberProvider) {
          issues.add(
            const TeamConfigIssue(
              TeamConfigIssueKind.teamDefaultProviderMissing,
            ),
          );
        }
        for (final member in members) {
          if (member.provider.trim().isEmpty) {
            issues.add(
              _memberIssue(TeamConfigIssueKind.memberProviderMissing, member),
            );
          } else if (await _needsModel(
            team.cli,
            member.provider,
            member.model,
          )) {
            issues.add(
              _memberIssue(TeamConfigIssueKind.memberModelMissing, member),
            );
          }
        }
      }
    }

    return TeamConfigValidation(
      teamId: team.id,
      teamName: team.name,
      mode: team.teamMode,
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
