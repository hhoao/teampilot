import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';

void main() {
  group('historyTurnInFlight', () {
    test('stop suppresses residual sessionWorking so Running chrome clears', () {
      // Compose Stop clears awaiting; PTY may still look working for idleAfter.
      expect(
        historyTurnInFlight(
          isSubmitting: false,
          awaitingAssistant: false,
          sessionWorking: true,
          userStoppedTurn: true,
        ),
        isFalse,
      );
    });

    test('sessionWorking alone keeps turn in flight until Stop', () {
      expect(
        historyTurnInFlight(
          isSubmitting: false,
          awaitingAssistant: false,
          sessionWorking: true,
          userStoppedTurn: false,
        ),
        isTrue,
      );
    });

    test('awaitingAssistant keeps turn in flight even after Stop latch', () {
      // Stop handler must clear awaiting; if it is still true, chrome stays.
      expect(
        historyTurnInFlight(
          isSubmitting: false,
          awaitingAssistant: true,
          sessionWorking: false,
          userStoppedTurn: true,
        ),
        isTrue,
      );
    });
  });

  group('SessionHistoryLiveChromeX.resolve', () {
    test('none when turn not in flight', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: false,
          memberRunning: false,
          sessionWorking: false,
          sessionConnecting: true,
        ),
        SessionHistoryLiveChrome.none,
      );
    });

    test('starting while connecting before PTY up', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionWorking: false,
          sessionConnecting: true,
        ),
        SessionHistoryLiveChrome.starting,
      );
    });

    test('starting when awaiting but member not running yet', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionWorking: false,
          sessionConnecting: false,
        ),
        SessionHistoryLiveChrome.starting,
      );
    });

    test('running once member PTY is up', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: true,
          sessionWorking: false,
          sessionConnecting: false,
        ),
        SessionHistoryLiveChrome.running,
      );
    });

    test('running while session working even if connecting flag stale', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionWorking: true,
          sessionConnecting: true,
        ),
        SessionHistoryLiveChrome.running,
      );
    });
  });
}
