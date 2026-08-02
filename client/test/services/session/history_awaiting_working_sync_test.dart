import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/history_awaiting_working_sync.dart';

void main() {
  group('resolveHistoryAwaitingWorkingAction', () {
    test('not awaiting → none / resetLatch', () {
      expect(
        resolveHistoryAwaitingWorkingAction(
          awaitingAssistant: false,
          sessionWorking: false,
          sawWorkingWhileAwaiting: false,
        ),
        HistoryAwaitingWorkingAction.none,
      );
      expect(
        resolveHistoryAwaitingWorkingAction(
          awaitingAssistant: false,
          sessionWorking: true,
          sawWorkingWhileAwaiting: true,
        ),
        HistoryAwaitingWorkingAction.resetLatch,
      );
    });

    test('awaiting + working → latch', () {
      expect(
        resolveHistoryAwaitingWorkingAction(
          awaitingAssistant: true,
          sessionWorking: true,
          sawWorkingWhileAwaiting: false,
        ),
        HistoryAwaitingWorkingAction.latchWorking,
      );
    });

    test('awaiting + idle after latch → clear (sidebar idle)', () {
      expect(
        resolveHistoryAwaitingWorkingAction(
          awaitingAssistant: true,
          sessionWorking: false,
          sawWorkingWhileAwaiting: true,
        ),
        HistoryAwaitingWorkingAction.clearAwaiting,
      );
    });

    test(
      'awaiting + idle without latch → grace clear '
      '(already-working-at-submit miss / never working)',
      () {
        expect(
          resolveHistoryAwaitingWorkingAction(
            awaitingAssistant: true,
            sessionWorking: false,
            sawWorkingWhileAwaiting: false,
            sessionConnecting: false,
            memberRunning: true,
          ),
          HistoryAwaitingWorkingAction.scheduleGraceClear,
        );
      },
    );

    test(
      'awaiting + connect / PTY-down defers — keep Starting, no grace',
      () {
        // Landing seed / first continue: workingSessionIds empty while connect
        // runs. Must not grace-clear awaiting (connect often > 4s).
        expect(
          resolveHistoryAwaitingWorkingAction(
            awaitingAssistant: true,
            sessionWorking: false,
            sawWorkingWhileAwaiting: false,
            sessionConnecting: true,
            memberRunning: false,
          ),
          HistoryAwaitingWorkingAction.deferWhileStarting,
        );
        expect(
          resolveHistoryAwaitingWorkingAction(
            awaitingAssistant: true,
            sessionWorking: false,
            sawWorkingWhileAwaiting: false,
            sessionConnecting: false,
            memberRunning: false,
          ),
          HistoryAwaitingWorkingAction.deferWhileStarting,
        );
      },
    );

    test('latched idle still clears even if connecting flag stale', () {
      // Falling edge after a real working turn wins over connect noise.
      expect(
        resolveHistoryAwaitingWorkingAction(
          awaitingAssistant: true,
          sessionWorking: false,
          sawWorkingWhileAwaiting: true,
          sessionConnecting: true,
          memberRunning: false,
        ),
        HistoryAwaitingWorkingAction.clearAwaiting,
      );
    });
  });
}
