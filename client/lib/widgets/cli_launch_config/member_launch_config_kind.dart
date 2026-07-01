import '../../models/team_config.dart';

/// High-level member launch configuration mode (maps to [MemberLaunchMode]).
enum MemberLaunchConfigKind {
  inheritTeam,
  preset,
  custom,
}

MemberLaunchConfigKind memberLaunchConfigKind(TeamMemberConfig member) {
  if (member.inheritsTeamPreset) return MemberLaunchConfigKind.inheritTeam;
  if (member.hasExplicitPreset) return MemberLaunchConfigKind.preset;
  return MemberLaunchConfigKind.custom;
}
