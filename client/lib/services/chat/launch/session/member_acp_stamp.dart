import '../../../../models/app_session.dart';
import '../../../../models/session_member_binding.dart';
import '../../../../models/team_config.dart';
import '../../session/chat_tab.dart';
import 'launch_acp_policy.dart';

bool _memberAcpSupported({required String targetId, required CliTool? cli}) =>
    acpAvailabilityFor(cli: cli, targetId: targetId) !=
    AcpAvailability.unsupported;

bool resolveMemberBindingAcp({
  required String targetId,
  required CliTool? cli,
  required bool requested,
}) {
  if (!_memberAcpSupported(targetId: targetId, cli: cli)) return false;
  return resolveAcpOnTarget(cli: cli, targetId: targetId, requested: requested);
}

bool _requestedMemberAcpSeed(
  CliTool? cli, {
  required bool seedClaudeMemberAcp,
  required bool seedCodexMemberAcp,
  required bool seedCursorMemberAcp,
  required bool seedOpencodeMemberAcp,
}) => switch (cli) {
  CliTool.claude => seedClaudeMemberAcp,
  CliTool.codex => seedCodexMemberAcp,
  CliTool.cursor => seedCursorMemberAcp,
  CliTool.opencode => seedOpencodeMemberAcp,
  _ => false,
};

/// Stamps member bindings with ACP from CLI settings seeds.
///
/// ACP-only CLIs are forced whenever the target supports ACP. Team session
/// `acp` stays on the session, not on this list. Every seat follows the CLI
/// preference; only the launch target's transport and the CLI's ACP capability
/// gate it.
List<SessionMemberBinding> stampMemberAcp({
  required List<SessionMemberBinding> members,
  required Map<String, String> memberTargets,
  required bool seedClaudeMemberAcp,
  required bool seedCodexMemberAcp,
  bool seedCursorMemberAcp = true,
  bool seedOpencodeMemberAcp = true,
  LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess,
}) {
  return [
    for (final member in members)
      _bindingWithAcp(member, switch (memberTargets[member.rosterMemberId]) {
        final String targetId => resolveMemberBindingAcp(
          targetId: targetId,
          cli: member.cli,
          requested: _requestedMemberAcpSeed(
            member.cli,
            seedClaudeMemberAcp: seedClaudeMemberAcp,
            seedCodexMemberAcp: seedCodexMemberAcp,
            seedCursorMemberAcp: seedCursorMemberAcp,
            seedOpencodeMemberAcp: seedOpencodeMemberAcp,
          ),
        ),
        null => false,
      }, acpPermission),
  ];
}

SessionMemberBinding _bindingWithAcp(
  SessionMemberBinding member,
  bool acp,
  LaunchSecurityPolicy acpPermission,
) {
  final resolvedPermission = acp
      ? acpPermission
      : LaunchSecurityPolicy.fullAccess;
  if (member.acp == acp && member.acpPermission == resolvedPermission) {
    return member;
  }
  return SessionMemberBinding(
    rosterMemberId: member.rosterMemberId,
    taskId: member.taskId,
    typeId: member.typeId,
    cli: member.cli,
    nativeSessionIds: member.nativeSessionIds,
    acp: acp,
    acpPermission: resolvedPermission,
  );
}

bool shouldAttachMemberAcp({
  required AppSession session,
  required String memberId,
  required String targetId,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpSupported(targetId: targetId, cli: cli);
}
