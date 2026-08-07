import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/terminal/exit_plan_mode_approval_service.dart';

void main() {
  test('approve completes the held hook with allow', () async {
    final gate = ExitPlanModeHookGate();
    final held = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
      timeout: const Duration(hours: 1),
    );
    final service = ExitPlanModeApprovalService(hookGate: gate);

    final result = await service.approve(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
    );

    expect(result, isA<ExitPlanApprovalOk>());
    final reply = await held;
    expect(reply?.deny, isFalse);
  });

  test('reject completes the held hook with deny', () async {
    final gate = ExitPlanModeHookGate();
    final held = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't2',
      timeout: const Duration(hours: 1),
    );
    final service = ExitPlanModeApprovalService(hookGate: gate);

    final result = await service.reject(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't2',
    );

    expect(result, isA<ExitPlanApprovalOk>());
    final reply = await held;
    expect(reply?.deny, isTrue);
  });

  test('no waiter → Failed', () async {
    final gate = ExitPlanModeHookGate();
    final service = ExitPlanModeApprovalService(hookGate: gate);
    final result = await service.approve(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 'nope',
    );
    expect(result, isA<ExitPlanApprovalFailed>());
  });
}
