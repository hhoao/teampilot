import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';
import 'package:teampilot/pages/chat/session_launch_error_visibility.dart';

void main() {
  test('hidden while connecting even if error set', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: 'boom',
        sessionConnectInProgress: true,
      ),
      isFalse,
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

  test('hidden when no error', () {
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
