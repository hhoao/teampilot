import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';

void main() {
  group('resolveChatWorkbenchOverlay', () {
    test('keeps History while connect is in progress (continue-from-History)', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.history,
          sessionConnectInProgress: true,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.history,
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

    test('shows History when idle on History view', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.history,
          sessionConnectInProgress: false,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.history,
      );
    });

    test('remote provision wins over History and connect spinner', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.history,
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
}
