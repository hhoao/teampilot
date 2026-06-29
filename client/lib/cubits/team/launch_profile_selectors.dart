import 'package:equatable/equatable.dart';

import '../../models/launch_profile_kind.dart';
import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import 'model/launch_profile_state.dart';

/// Sidebar identity list — stable across per-member field edits.
class HomeSidebarIdentitySnapshot extends Equatable {
  const HomeSidebarIdentitySnapshot({
    required this.personals,
    required this.teams,
  });

  final List<IdentitySidebarEntry> personals;
  final List<IdentitySidebarEntry> teams;

  @override
  List<Object?> get props => [personals, teams];
}

class IdentitySidebarEntry extends Equatable {
  const IdentitySidebarEntry({
    required this.id,
    required this.display,
    required this.kind,
  });

  final String id;
  final String display;
  final LaunchProfileKind kind;

  @override
  List<Object?> get props => [id, display, kind];
}

/// Member picker chips — rebuild when roster ids/names/lead flags change.
class MemberRosterEntry extends Equatable {
  const MemberRosterEntry({
    required this.id,
    required this.displayName,
    required this.isTeamLead,
  });

  final String id;
  final String displayName;
  final bool isTeamLead;

  @override
  List<Object?> get props => [id, displayName, isTeamLead];
}

/// Home team header — name + mode only.
class TeamHeaderSnapshot extends Equatable {
  const TeamHeaderSnapshot({
    required this.id,
    required this.display,
    required this.teamMode,
  });

  final String id;
  final String display;
  final TeamMode teamMode;

  @override
  List<Object?> get props => [id, display, teamMode];
}

/// Team fields used by [TeamMemberConfigForm] besides the active member.
class TeamMemberFormShell extends Equatable {
  const TeamMemberFormShell({
    required this.id,
    required this.teamMode,
    required this.cli,
    required this.memberCount,
  });

  final String id;
  final TeamMode teamMode;
  final CliTool cli;
  final int memberCount;

  @override
  List<Object?> get props => [id, teamMode, cli, memberCount];
}

/// Launch summary row inputs — stable when prompt/name text fields change.
class MemberLaunchContext extends Equatable {
  const MemberLaunchContext({
    required this.teamId,
    required this.teamMode,
    required this.teamCli,
    required this.teamActivePresetId,
    required this.memberId,
    required this.memberCli,
    required this.memberProvider,
    required this.memberModel,
    required this.memberEffort,
    required this.memberActivePresetId,
  });

  final String teamId;
  final TeamMode teamMode;
  final CliTool teamCli;
  final String? teamActivePresetId;
  final String memberId;
  final CliTool? memberCli;
  final String memberProvider;
  final String memberModel;
  final String memberEffort;
  final String? memberActivePresetId;

  CliTool get catalogCli =>
      teamMode == TeamMode.mixed ? (memberCli ?? teamCli) : teamCli;

  factory MemberLaunchContext.from(TeamProfile team, TeamMemberConfig member) {
    return MemberLaunchContext(
      teamId: team.id,
      teamMode: team.teamMode,
      teamCli: team.cli,
      teamActivePresetId: team.activePresetId,
      memberId: member.id,
      memberCli: member.cli,
      memberProvider: member.provider,
      memberModel: member.model,
      memberEffort: member.effort,
      memberActivePresetId: member.activePresetId,
    );
  }

  @override
  List<Object?> get props => [
    teamId,
    teamMode,
    teamCli,
    teamActivePresetId,
    memberId,
    memberCli,
    memberProvider,
    memberModel,
    memberEffort,
    memberActivePresetId,
  ];
}

/// Discrete member toggles — excludes text fields edited locally in the form.
class MemberDiscreteFields extends Equatable {
  const MemberDiscreteFields({
    required this.dangerouslySkipPermissions,
    required this.replicas,
    required this.isTeamLead,
  });

  final bool dangerouslySkipPermissions;
  final int replicas;
  final bool isTeamLead;

  factory MemberDiscreteFields.from(TeamMemberConfig member) {
    return MemberDiscreteFields(
      dangerouslySkipPermissions: member.dangerouslySkipPermissions,
      replicas: member.replicas,
      isTeamLead: TeamMemberNaming.isTeamLead(member),
    );
  }

  @override
  List<Object?> get props => [dangerouslySkipPermissions, replicas, isTeamLead];
}

abstract final class LaunchProfileSelectors {
  LaunchProfileSelectors._();

  static HomeSidebarIdentitySnapshot sidebarIdentities(
    LaunchProfileState state,
  ) {
    return HomeSidebarIdentitySnapshot(
      personals: [
        for (final personal in state.personals)
          IdentitySidebarEntry(
            id: personal.id,
            display: personal.display,
            kind: personal.kind,
          ),
      ],
      teams: [
        for (final team in state.teams)
          IdentitySidebarEntry(
            id: team.id,
            display: team.display,
            kind: team.kind,
          ),
      ],
    );
  }

  static TeamProfile? teamById(LaunchProfileState state, String teamId) {
    final identity = state.byId(teamId);
    return identity is TeamProfile ? identity : null;
  }

  static TeamHeaderSnapshot? teamHeader(TeamProfile? team) {
    if (team == null) return null;
    return TeamHeaderSnapshot(
      id: team.id,
      display: team.display,
      teamMode: team.teamMode,
    );
  }

  static TeamMemberFormShell? memberFormShell(TeamProfile? team) {
    if (team == null) return null;
    return TeamMemberFormShell(
      id: team.id,
      teamMode: team.teamMode,
      cli: team.cli,
      memberCount: team.members.length,
    );
  }

  static List<MemberRosterEntry> memberRoster(TeamProfile? team) {
    if (team == null) return const [];
    return [
      for (final member in team.members)
        MemberRosterEntry(
          id: member.id,
          displayName: member.name.trim().isEmpty ? member.id : member.name,
          isTeamLead: TeamMemberNaming.isTeamLead(member),
        ),
    ];
  }

  static TeamMemberConfig? memberById(TeamProfile? team, String? memberId) {
    final id = memberId;
    if (team == null || id == null || team.members.isEmpty) return null;
    for (final member in team.members) {
      if (member.id == id) return member;
    }
    return null;
  }

  static MemberLaunchContext? memberLaunchContext(
    LaunchProfileState state,
    String teamId,
    String memberId,
  ) {
    final team = teamById(state, teamId);
    final member = memberById(team, memberId);
    if (team == null || member == null) return null;
    return MemberLaunchContext.from(team, member);
  }

  static MemberDiscreteFields? memberDiscreteFields(
    LaunchProfileState state,
    String teamId,
    String memberId,
  ) {
    final member = memberById(teamById(state, teamId), memberId);
    if (member == null) return null;
    return MemberDiscreteFields.from(member);
  }
}
