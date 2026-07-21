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
}
