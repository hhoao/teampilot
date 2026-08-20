import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/member_input_ready_wait.dart';

void main() {
  const running = MemberShellReadySnapshot(
    startFailed: false,
    isConnecting: false,
    isRunning: true,
    isConnected: true,
  );
  const idle = MemberShellReadySnapshot(
    startFailed: false,
    isConnecting: false,
    isRunning: false,
    isConnected: false,
  );
  const failed = MemberShellReadySnapshot(
    startFailed: true,
    isConnecting: false,
    isRunning: false,
    isConnected: false,
  );

  test('idle shell that never ran is not dead', () {
    expect(
      memberInputWaitShouldAbortDead(shell: idle, sawRunning: false),
      isFalse,
    );
  });

  test('startFailed is dead even if it never ran', () {
    expect(
      memberInputWaitShouldAbortDead(shell: failed, sawRunning: false),
      isTrue,
    );
  });

  test('process that ran then went idle is dead', () {
    expect(
      memberInputWaitShouldAbortDead(shell: idle, sawRunning: true),
      isTrue,
    );
  });

  test('running shell is not dead', () {
    expect(
      memberInputWaitShouldAbortDead(shell: running, sawRunning: true),
      isFalse,
    );
  });

  test('default cap is 10 minutes', () {
    expect(defaultMemberInputReadyCap, const Duration(minutes: 10));
  });

  test('cap fires after waitCap elapses, not at 120s', () {
    final started = DateTime(2026, 8, 20, 11, 14, 57);
    expect(
      memberInputWaitTimedOut(
        startedAt: started,
        cap: const Duration(minutes: 10),
        now: started.add(const Duration(minutes: 10)),
      ),
      isTrue,
    );
    expect(
      memberInputWaitTimedOut(
        startedAt: started,
        cap: const Duration(minutes: 10),
        now: started.add(const Duration(seconds: 120)),
      ),
      isFalse,
    );
  });
}
