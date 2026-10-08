/// Outcome of [SessionLaunchService.requestOpenSession].
enum SessionOpenStatus {
  opened,
  blockedMixedMemberTargets,
  missingWorkspace,
  missingTeamMember,
}
