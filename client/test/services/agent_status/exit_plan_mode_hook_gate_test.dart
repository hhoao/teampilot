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

  test('completeSeat resolves every waiter for the seat', () async {
    final gate = ExitPlanModeHookGate();
    final a = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't5',
      timeout: const Duration(hours: 1),
    );
    final b = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't6',
      timeout: const Duration(hours: 1),
    );
    final other = gate.wait(
      sessionId: 's',
      memberId: 'other',
      toolUseId: 't7',
      timeout: const Duration(milliseconds: 30),
    );
    expect(
      gate.completeSeat(
        sessionId: 's',
        memberId: 'm',
        reply: const ExitPlanModeHookReply.allow(),
      ),
      isTrue,
    );
    expect((await a)?.deny, isFalse);
    expect((await b)?.deny, isFalse);
    expect(
      gate.hasWaiter(sessionId: 's', memberId: 'other', toolUseId: 't7'),
      isTrue,
    );
    await other;
  });

  group('ExitPlanPermissionRequestGate', () {
    test('wait registers a waiter; complete resolves allow', () async {
      final gate = ExitPlanPermissionRequestGate();
      final future = gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 500),
      );
      expect(
        gate.complete(
          sessionId: 's',
          memberId: 'm',
          reply: const ExitPlanPermissionRequestReply.allow(),
        ),
        isTrue,
      );
      final reply = await future;
      expect(reply?.deny, isFalse);
      expect(reply?.toHookResponse(), {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {'behavior': 'allow'},
        },
      });
    });

    test('deny reply serializes the decision message', () {
      expect(const ExitPlanPermissionRequestReply.deny().toHookResponse(), {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {'behavior': 'deny', 'message': 'User rejected the plan'},
        },
      });
    });

    test('complete with no waiter returns false', () {
      final gate = ExitPlanPermissionRequestGate();
      expect(
        gate.complete(
          sessionId: 's',
          memberId: 'm',
          reply: const ExitPlanPermissionRequestReply.deny(),
        ),
        isFalse,
      );
    });

    test('wait times out and returns null', () async {
      final gate = ExitPlanPermissionRequestGate();
      final reply = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      expect(reply, isNull);
    });

    test('remembered decision auto-applies to a matching wait', () async {
      final gate = ExitPlanPermissionRequestGate();
      gate.remember(
        sessionId: 's',
        memberId: 'm',
        deny: false,
        planFingerprint: 'plan-a',
      );
      final reply = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      expect(reply?.deny, isFalse);
    });

    test('remembered decision does not match a different plan', () async {
      final gate = ExitPlanPermissionRequestGate();
      gate.remember(
        sessionId: 's',
        memberId: 'm',
        deny: true,
        planFingerprint: 'plan-a',
      );
      final reply = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-b',
        timeout: const Duration(milliseconds: 30),
      );
      expect(reply, isNull);
    });

    test('remembered decision is consumed once', () async {
      final gate = ExitPlanPermissionRequestGate();
      gate.remember(
        sessionId: 's',
        memberId: 'm',
        deny: false,
        planFingerprint: 'plan-a',
      );
      final first = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      expect(first?.deny, isFalse);
      final second = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      expect(second, isNull);
    });

    test('forget drops the remembered decision', () async {
      final gate = ExitPlanPermissionRequestGate();
      gate.remember(
        sessionId: 's',
        memberId: 'm',
        deny: false,
        planFingerprint: 'plan-a',
      );
      gate.forget(sessionId: 's', memberId: 'm');
      final reply = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      expect(reply, isNull);
    });

    test(
      'clearSeat resolves pending waiters as deny and drops memory',
      () async {
        final gate = ExitPlanPermissionRequestGate();
        final future = gate.wait(
          sessionId: 's',
          memberId: 'm',
          planFingerprint: 'plan-a',
          timeout: const Duration(hours: 1),
        );
        gate.remember(
          sessionId: 's',
          memberId: 'm',
          deny: false,
          planFingerprint: 'plan-b',
        );
        gate.clearSeat(sessionId: 's', memberId: 'm');
        expect((await future)?.deny, isTrue);
        final late = await gate.wait(
          sessionId: 's',
          memberId: 'm',
          planFingerprint: 'plan-b',
          timeout: const Duration(milliseconds: 30),
        );
        expect(late, isNull);
      },
    );

    test('clearSession resolves pending waiters as deny', () async {
      final gate = ExitPlanPermissionRequestGate();
      final future = gate.wait(
        sessionId: 's',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(hours: 1),
      );
      final other = gate.wait(
        sessionId: 'other',
        memberId: 'm',
        planFingerprint: 'plan-a',
        timeout: const Duration(milliseconds: 30),
      );
      gate.clearSession('s');
      expect((await future)?.deny, isTrue);
      // Other sessions keep waiting (resolve via timeout).
      expect(await other, isNull);
    });
  });
}
