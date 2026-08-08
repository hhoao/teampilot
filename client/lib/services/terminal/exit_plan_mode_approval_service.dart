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

/// Completes a held Claude-family ExitPlanMode `PreToolUse` hook with the
/// official allow/deny decision from the chat card.
final class ExitPlanModeApprovalService {
  ExitPlanModeApprovalService({ExitPlanModeHookGate? hookGate})
    : _hookGate = hookGate;

  final ExitPlanModeHookGate? _hookGate;

  Future<ExitPlanApprovalResult> approve({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) => _complete(
    sessionId: sessionId,
    memberId: memberId,
    toolUseId: toolUseId,
    reply: const ExitPlanModeHookReply.allow(),
  );

  Future<ExitPlanApprovalResult> reject({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) => _complete(
    sessionId: sessionId,
    memberId: memberId,
    toolUseId: toolUseId,
    reply: const ExitPlanModeHookReply.deny(),
  );

  Future<ExitPlanApprovalResult> _complete({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    required ExitPlanModeHookReply reply,
  }) async {
    final gate = _hookGate;
    final id = toolUseId.trim();
    if (gate == null || id.isEmpty) {
      return const ExitPlanApprovalFailed('no_pending_approval');
    }
    final ok = gate.complete(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: id,
      reply: reply,
    );
    return ok
        ? const ExitPlanApprovalOk()
        : const ExitPlanApprovalFailed('no_pending_approval');
  }
}
