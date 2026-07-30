import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';

void main() {
  group('resolveChatWorkbenchOverlay', () {
    test('keeps Chat while connect is in progress (continue-from-Chat)', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.chat,
          sessionConnectInProgress: true,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.chat,
      );
    });

    test('shows sessionStarting when Terminal connects', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.terminal,
          sessionConnectInProgress: true,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.sessionStarting,
      );
    });

    test('shows Chat overlay when idle on Chat view', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.chat,
          sessionConnectInProgress: false,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.chat,
      );
    });

    test('remote provision wins over Chat and connect spinner', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.chat,
          sessionConnectInProgress: true,
          showRemoteProvision: true,
        ),
        ChatWorkbenchOverlay.remoteProvision,
      );
    });

    test('none when Terminal and not connecting', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.terminal,
          sessionConnectInProgress: false,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.none,
      );
    });
  });

  group('shouldMountWorkbenchTerminal', () {
    test('mounts while running or connecting', () {
      expect(
        shouldMountWorkbenchTerminal(
          sessionConnectInProgress: true,
          sessionRunning: false,
          showRemoteProvision: false,
          hasLaunchError: false,
        ),
        isTrue,
      );
      expect(
        shouldMountWorkbenchTerminal(
          sessionConnectInProgress: false,
          sessionRunning: true,
          showRemoteProvision: false,
          hasLaunchError: false,
        ),
        isTrue,
      );
    });

    test('keeps terminal mounted after exit when launchError is set', () {
      expect(
        shouldMountWorkbenchTerminal(
          sessionConnectInProgress: false,
          sessionRunning: false,
          showRemoteProvision: false,
          hasLaunchError: true,
        ),
        isTrue,
      );
    });

    test('does not mount when idle with no error', () {
      expect(
        shouldMountWorkbenchTerminal(
          sessionConnectInProgress: false,
          sessionRunning: false,
          showRemoteProvision: false,
          hasLaunchError: false,
        ),
        isFalse,
      );
    });
  });
}
