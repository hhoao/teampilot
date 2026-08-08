import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';

void main() {
  test('wait registers a waiter; complete resolves allow', () async {
    final gate = ExitPlanModeHookGate();
    final future = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
      timeout: const Duration(milliseconds: 500),
    );
    expect(
      gate.hasWaiter(sessionId: 's', memberId: 'm', toolUseId: 't1'),
      isTrue,
    );
    expect(
      gate.complete(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 't1',
        reply: const ExitPlanModeHookReply.allow(),
      ),
      isTrue,
    );
    final reply = await future;
    expect(reply?.deny, isFalse);
    expect(
      gate.hasWaiter(sessionId: 's', memberId: 'm', toolUseId: 't1'),
      isFalse,
    );
  });

  test('complete with no waiter returns false', () {
    final gate = ExitPlanModeHookGate();
    expect(
      gate.complete(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 'nope',
        reply: const ExitPlanModeHookReply.deny(),
      ),
      isFalse,
    );
  });

  test('wait times out and returns null', () async {
    final gate = ExitPlanModeHookGate();
    final reply = await gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't3',
      timeout: const Duration(milliseconds: 30),
    );
    expect(reply, isNull);
  });

  test('clearSeat resolves pending waiters as deny', () async {
    final gate = ExitPlanModeHookGate();
    final future = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't4',
      timeout: const Duration(hours: 1),
    );
    gate.clearSeat(sessionId: 's', memberId: 'm');
    final reply = await future;
    expect(reply?.deny, isTrue);
  });
}
