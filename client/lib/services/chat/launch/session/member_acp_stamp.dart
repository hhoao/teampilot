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

/// Targets that have an ACP transport: local spawn, SSH exec, or the synthetic
/// Termux loopback profile. WSL seats have no exec channel, so they stay PTY.
bool _memberAcpTargetSupported(String targetId) {
  final kind = runtimeKindOfId(targetId);
  return kind == RuntimeKind.local || usesSshTransport(kind);
}

bool _memberAcpGates({
  required String targetId,
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (_isAndroid(isAndroidOverride)) return false;
  if (!_memberAcpTargetSupported(targetId)) return false;
  if (cli == null) return false;
  final registry = CliToolRegistry.builtIn();
  if (registry.capability<AcpCapability>(cli) == null) return false;
  if (registry.capability<AcpLocalOnlyCapability>(cli) != null &&
      runtimeKindOfId(targetId) != RuntimeKind.local) {
    return false;
  }
  return true;
}

bool resolveMemberBindingAcp({
  required String targetId,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!_memberAcpGates(
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

/// Stamps member bindings with ACP from CLI settings seeds.
///
/// Gemini is true whenever the gates pass. Team session `acp` stays on the
/// session, not on this list. Every seat follows the CLI preference; only the
/// platform, the launch target's transport, and the CLI's ACP capability gate
/// it.
List<SessionMemberBinding> stampMemberAcp({
  required List<SessionMemberBinding> members,
  required Map<String, String> memberTargets,
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
        switch (memberTargets[member.rosterMemberId]) {
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
            isAndroidOverride: isAndroidOverride,
          ),
          null => false,
        },
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
  required String targetId,
  bool? isAndroidOverride,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpGates(
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  );
}
