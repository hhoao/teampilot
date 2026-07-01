import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/member_turn_idle_sync.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

class _RunningShell extends TerminalSession {
  _RunningShell() : super(executable: 'true', validateLaunch: false);

  @override
  bool get isRunning => true;
}

void main() {
  test('ends turn when fingerprint unchanged for idleAfter', () async {
    final shell = _RunningShell();
    final wasInTurn = <String, bool>{};
    var ended = false;

    shell.activityTracker.reset();
    MemberTurnIdleSync.tick(
      turnKey: 'tab:m',
      inTurn: true,
      shell: shell,
      wasInTurn: wasInTurn,
      endTurn: () => ended = true,
    );
    shell.activityTracker.latchTurnQuietBaseline(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    expect(
      MemberTurnIdleSync.tick(
        turnKey: 'tab:m',
        inTurn: true,
        shell: shell,
        wasInTurn: wasInTurn,
        endTurn: () => ended = true,
      ),
      isFalse,
    );
    expect(ended, isTrue);
  });

  test('does not end turn immediately after latch', () {
    final shell = _RunningShell();
    final wasInTurn = <String, bool>{};
    var ended = false;

    expect(
      MemberTurnIdleSync.tick(
        turnKey: 'tab:m',
        inTurn: true,
        shell: shell,
        wasInTurn: wasInTurn,
        endTurn: () => ended = true,
      ),
      isTrue,
      reason: 'within idleAfter after latch, no PTY yet',
    );
    expect(ended, isFalse);
  });
}
