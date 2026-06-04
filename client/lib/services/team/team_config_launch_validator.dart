import 'package:equatable/equatable.dart';

import '../../models/team_config.dart';

/// One missing piece of team configuration that should be filled before a
/// session can launch with a usable provider/model (and CLI, in mixed mode).
enum TeamConfigIssueKind {
  /// native: team has no explicit default provider for its CLI, and members
  /// don't supply their own provider either.
  teamDefaultProviderMissing,

  /// A member has no provider configured.
  memberProviderMissing,

  /// A member has no model configured.
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

/// Pre-launch check that a team has enough provider/model/CLI configuration to
/// start a session. Pure (presence-based) and synchronous so it is cheap to run
/// on every team-session open and trivially unit-testable.
///
/// Rules:
/// - **native**: a session uses one CLI ([TeamConfig.cli]). It is satisfied when
///   the team has an explicit default provider for that CLI
///   (`providerIdsByTool[cli]`, strict — global "sole provider" fallback is not
///   counted). Without a team default, every valid member must instead carry
///   their own provider + model.
/// - **mixed**: each valid member runs its own CLI, so each must have a CLI
///   override, a provider, and a model.
class TeamConfigLaunchValidator {
  const TeamConfigLaunchValidator();

  TeamConfigValidation validate(TeamConfig team) {
    final members = team.members.where((m) => m.isValid).toList(growable: false);
    final issues = <TeamConfigIssue>[];

    if (team.teamMode == TeamMode.mixed) {
      for (final member in members) {
        if (member.cli == null) {
          issues.add(_memberIssue(TeamConfigIssueKind.memberCliMissing, member));
        }
        if (member.provider.trim().isEmpty) {
          issues.add(
            _memberIssue(TeamConfigIssueKind.memberProviderMissing, member),
          );
        }
        if (member.model.trim().isEmpty) {
          issues.add(
            _memberIssue(TeamConfigIssueKind.memberModelMissing, member),
          );
        }
      }
    } else {
      final hasTeamDefault =
          (team.providerIdsByTool[team.cli.value] ?? '').trim().isNotEmpty;
      if (!hasTeamDefault) {
        final anyMemberProvider =
            members.any((m) => m.provider.trim().isNotEmpty);
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
          }
          if (member.model.trim().isEmpty) {
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

  TeamConfigIssue _memberIssue(
    TeamConfigIssueKind kind,
    TeamMemberConfig member,
  ) =>
      TeamConfigIssue(kind, memberId: member.id, memberName: member.name);
}
