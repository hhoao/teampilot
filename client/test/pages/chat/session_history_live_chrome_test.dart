import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';

void main() {
  group('historyTurnInFlight', () {
    test('stop suppresses residual sessionBusy so Running chrome clears', () {
      // Compose Stop clears awaiting; PTY may still look busy for idleAfter.
      expect(
        historyTurnInFlight(
          isSubmitting: false,
          awaitingAssistant: false,
          sessionBusy: true,
          userStoppedTurn: true,
        ),
        isFalse,
      );
    });

    test('sessionBusy alone keeps turn in flight until Stop', () {
      expect(
        historyTurnInFlight(
          isSubmitting: false,
          awaitingAssistant: false,
          sessionBusy: true,
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
          sessionBusy: false,
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
          sessionConnecting: false,
        ),
        SessionHistoryLiveChrome.starting,
      );
    });

    test('starting when delivering and member not running yet', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionConnecting: false,
          isDelivering: true,
        ),
        SessionHistoryLiveChrome.starting,
      );
    });

    test('starting when delivering even if member PTY is up', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: true,
          sessionConnecting: false,
          isDelivering: true,
        ),
        SessionHistoryLiveChrome.starting,
      );
    });

    test('running once member PTY is up', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: true,
          sessionConnecting: false,
        ),
        SessionHistoryLiveChrome.running,
      );
    });

    test('running when inTurn even if member not running yet', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionConnecting: false,
          isInTurn: true,
        ),
        SessionHistoryLiveChrome.running,
      );
    });

    test('running when attention even if delivering', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionConnecting: false,
          isDelivering: true,
          isAttention: true,
        ),
        SessionHistoryLiveChrome.running,
      );
    });

    test('running while inTurn even if connecting flag stale', () {
      expect(
        SessionHistoryLiveChromeX.resolve(
          turnInFlight: true,
          memberRunning: false,
          sessionConnecting: true,
          isInTurn: true,
        ),
        SessionHistoryLiveChrome.running,
      );
    });
  });
}
