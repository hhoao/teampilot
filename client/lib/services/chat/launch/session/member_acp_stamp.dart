import 'dart:io' show Platform;

import '../../../../models/app_session.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/session_member_binding.dart';
import '../../../../models/team_config.dart';
import '../../session/chat_tab.dart';
import '../../../cli/registry/capabilities/acp_capability.dart';
import '../../../cli/registry/cli_tool_registry.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

bool _memberAcpGates({
  required TeamMode teamMode,
  required String targetId,
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (teamMode != TeamMode.mixed) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  if (runtimeKindOfId(targetId) != RuntimeKind.local) return false;
  if (cli == null) return false;
  return CliToolRegistry.builtIn().capability<AcpCapability>(cli) != null;
}

bool resolveMemberBindingAcp({
  required CliTool? cli,
  required TeamMode teamMode,
  required String targetId,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!_memberAcpGates(
    teamMode: teamMode,
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  )) {
    return false;
  }
  if (CliToolRegistry.builtIn().launchesAcpOnly(cli)) return true;
  return requested;
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

/// Stamps mixed local member bindings with ACP from CLI settings seeds.
///
/// Gemini is true whenever the mixed-local gates pass. Team session `acp`
/// stays on the session, not on this list. Native teams stay false.
List<SessionMemberBinding> stampMemberAcp({
  required List<SessionMemberBinding> members,
  required Map<String, String> memberTargets,
  required TeamMode teamMode,
  required bool seedClaudeMemberAcp,
  required bool seedCodexMemberAcp,
  bool seedCursorMemberAcp = true,
  bool seedOpencodeMemberAcp = true,
  LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess,
  bool? isAndroidOverride,
}) {
  return [
    for (final member in members)
      _bindingWithAcp(
        member,
        memberTargets[member.rosterMemberId] == null
            ? false
            : resolveMemberBindingAcp(
                cli: member.cli,
                teamMode: teamMode,
                targetId: memberTargets[member.rosterMemberId]!,
                requested: _requestedMemberAcpSeed(
                  member.cli,
                  seedClaudeMemberAcp: seedClaudeMemberAcp,
                  seedCodexMemberAcp: seedCodexMemberAcp,
                  seedCursorMemberAcp: seedCursorMemberAcp,
                  seedOpencodeMemberAcp: seedOpencodeMemberAcp,
                ),
                isAndroidOverride: isAndroidOverride,
              ),
        acpPermission,
      ),
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
  required TeamProfile? team,
  required String targetId,
  bool? isAndroidOverride,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpGates(
    teamMode: team?.teamMode ?? TeamMode.native,
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  );
}
