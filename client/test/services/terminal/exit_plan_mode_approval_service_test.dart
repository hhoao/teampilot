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
    final service = ExitPlanModeApprovalService(
      hookGate: gate,
      permissionGate: ExitPlanPermissionRequestGate(),
    );

    final result = await service.approve(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
      planText: 'plan-a',
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
    final service = ExitPlanModeApprovalService(
      hookGate: gate,
      permissionGate: ExitPlanPermissionRequestGate(),
    );

    final result = await service.reject(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't2',
      planText: 'plan-a',
    );

    expect(result, isA<ExitPlanApprovalOk>());
    final reply = await held;
    expect(reply?.deny, isTrue);
  });

  test('no waiter on either gate → Failed', () async {
    final gate = ExitPlanModeHookGate();
    final service = ExitPlanModeApprovalService(
      hookGate: gate,
      permissionGate: ExitPlanPermissionRequestGate(),
    );
    final result = await service.approve(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 'nope',
      planText: 'plan-a',
    );
    expect(result, isA<ExitPlanApprovalFailed>());
  });

  test(
    'approve completes an open PermissionRequest hook for the seat',
    () async {
      final gate = ExitPlanModeHookGate();
      final permissionGate = ExitPlanPermissionRequestGate();
      final held = permissionGate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(hours: 1),
      );
      final service = ExitPlanModeApprovalService(
        hookGate: gate,
        permissionGate: permissionGate,
      );

      final result = await service.approve(
        sessionId: 's',
        memberId: 'm',
        toolUseId: '',
        planText: 'plan-a',
      );

      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isFalse);
    },
  );

  test(
    'approve with empty toolUseId completes all seat PreToolUse hooks',
    () async {
      final gate = ExitPlanModeHookGate();
      final held = gate.wait(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 't3',
        timeout: const Duration(hours: 1),
      );
      final service = ExitPlanModeApprovalService(
        hookGate: gate,
        permissionGate: ExitPlanPermissionRequestGate(),
      );

      final result = await service.approve(
        sessionId: 's',
        memberId: 'm',
        toolUseId: '',
      );

      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isFalse);
    },
  );

  test(
    'approve remembers the decision for a later PermissionRequest hook',
    () async {
      final gate = ExitPlanModeHookGate();
      final held = gate.wait(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 't4',
        timeout: const Duration(hours: 1),
      );
      final permissionGate = ExitPlanPermissionRequestGate();
      final service = ExitPlanModeApprovalService(
        hookGate: gate,
        permissionGate: permissionGate,
      );

      final result = await service.reject(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 't4',
        planText: 'plan-a',
      );
      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isTrue);

      // The PermissionRequest hook arrives afterwards and auto-applies the
      // remembered rejection.
      final echo = await permissionGate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      expect(echo?.deny, isTrue);
    },
  );
}
