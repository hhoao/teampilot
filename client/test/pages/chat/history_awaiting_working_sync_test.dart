import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/history_awaiting_working_sync.dart';

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
        ),
        HistoryAwaitingWorkingAction.scheduleGraceClear,
      );
    },
  );

  test(
    'missed falling edge: awaiting true while already idle clears on reconcile',
    () {
      // Remount / post-load sync when workingSessionIds is already empty.
      expect(
        resolveHistoryAwaitingWorkingAction(
          awaitingAssistant: true,
          sessionWorking: false,
          sawWorkingWhileAwaiting: true,
        ),
        HistoryAwaitingWorkingAction.clearAwaiting,
      );
    },
  );

  test('history remount while idle clears awaiting without latch', () {
    expect(
      shouldClearAwaitingOnHistoryRemount(
        awaitingAssistant: true,
        sessionWorking: false,
      ),
      isTrue,
    );
    expect(
      shouldClearAwaitingOnHistoryRemount(
        awaitingAssistant: true,
        sessionWorking: true,
      ),
      isFalse,
    );
    expect(
      shouldClearAwaitingOnHistoryRemount(
        awaitingAssistant: false,
        sessionWorking: false,
      ),
      isFalse,
    );
  });
});
}
