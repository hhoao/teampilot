import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';

void main() {
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
