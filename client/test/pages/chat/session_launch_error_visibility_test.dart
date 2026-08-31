import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';
import 'package:teampilot/pages/chat/session_launch_error_visibility.dart';

void main() {
  test('shown while reconnecting after a failure so Retry can spin', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: 'boom',
        sessionConnectInProgress: true,
      ),
      isTrue,
    );
  });

  test('shown when failed and idle', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: 'boom',
        sessionConnectInProgress: false,
      ),
      isTrue,
    );
  });

  test('hidden when no error even if connecting (ordinary send/connect)', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: null,
        sessionConnectInProgress: true,
      ),
      isFalse,
    );
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: null,
        sessionConnectInProgress: false,
      ),
      isFalse,
    );
  });

  test('terminal banner only when overlay is none', () {
    expect(
      shouldShowTerminalSessionLaunchErrorBanner(
        overlay: ChatWorkbenchOverlay.none,
        launchError: 'boom',
        sessionConnectInProgress: false,
      ),
      isTrue,
    );
    expect(
      shouldShowTerminalSessionLaunchErrorBanner(
        overlay: ChatWorkbenchOverlay.sessionStarting,
        launchError: 'boom',
        sessionConnectInProgress: true,
      ),
      isFalse,
    );
    expect(
      shouldShowTerminalSessionLaunchErrorBanner(
        overlay: ChatWorkbenchOverlay.chat,
        launchError: 'boom',
        sessionConnectInProgress: false,
      ),
      isFalse,
    );
  });
}
