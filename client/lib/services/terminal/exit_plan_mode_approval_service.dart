import '../agent_status/exit_plan_mode.dart';
import '../agent_status/exit_plan_mode_hook_gate.dart';

sealed class ExitPlanApprovalResult {
  const ExitPlanApprovalResult();
}

final class ExitPlanApprovalOk extends ExitPlanApprovalResult {
  const ExitPlanApprovalOk();
}

final class ExitPlanApprovalFailed extends ExitPlanApprovalResult {
  const ExitPlanApprovalFailed(this.reason);
  final String reason;
}

/// Completes held Claude-family ExitPlanMode hooks with the official
/// allow/deny decision from the chat card.
///
/// Claude Code asks twice for a plan: the held `PreToolUse` hook (card with
/// buttons) and the follow-up `PermissionRequest` (native TUI prompt). One
/// card click answers both — the `PreToolUse` gate directly, and the
/// `PermissionRequest` gate when its hook is already open, or via decision
/// memory for the hook that arrives afterwards.
final class ExitPlanModeApprovalService {
  ExitPlanModeApprovalService({
    ExitPlanModeHookGate? hookGate,
    ExitPlanPermissionRequestGate? permissionGate,
  }) : _hookGate = hookGate,
       _permissionGate = permissionGate;

  final ExitPlanModeHookGate? _hookGate;
  final ExitPlanPermissionRequestGate? _permissionGate;

  Future<ExitPlanApprovalResult> approve({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    String? planText,
    String? planFilePath,
  }) => _complete(
    sessionId: sessionId,
    memberId: memberId,
    toolUseId: toolUseId,
    deny: false,
    planText: planText,
    planFilePath: planFilePath,
  );

  Future<ExitPlanApprovalResult> reject({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    String? planText,
    String? planFilePath,
  }) => _complete(
    sessionId: sessionId,
    memberId: memberId,
    toolUseId: toolUseId,
    deny: true,
    planText: planText,
    planFilePath: planFilePath,
  );

  Future<ExitPlanApprovalResult> _complete({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    required bool deny,
    String? planText,
    String? planFilePath,
  }) async {
    final hookReply = deny
        ? const ExitPlanModeHookReply.deny()
        : const ExitPlanModeHookReply.allow();
    final permissionReply = deny
        ? const ExitPlanPermissionRequestReply.deny()
        : const ExitPlanPermissionRequestReply.allow();

    var handled = false;
    final gate = _hookGate;
    if (gate != null) {
      final id = toolUseId.trim();
      handled = id.isNotEmpty
          ? gate.complete(
              sessionId: sessionId,
              memberId: memberId,
              toolUseId: id,
              reply: hookReply,
            )
          : gate.completeSeat(
              sessionId: sessionId,
              memberId: memberId,
              reply: hookReply,
            );
    }

    final permissionGate = _permissionGate;
    if (permissionGate != null) {
      final completed = permissionGate.complete(
        sessionId: sessionId,
        memberId: memberId,
        reply: permissionReply,
      );
      if (completed) {
        handled = true;
      } else {
        // The PermissionRequest hook usually arrives after the PreToolUse
        // hook resolves — remember the decision so it can auto-apply.
        permissionGate.remember(
          sessionId: sessionId,
          memberId: memberId,
          deny: deny,
          planFingerprint: exitPlanModeFingerprint(
            planText: planText,
            planFilePath: planFilePath,
          ),
        );
      }
    }

    return handled
        ? const ExitPlanApprovalOk()
        : const ExitPlanApprovalFailed('no_pending_approval');
  }
}
