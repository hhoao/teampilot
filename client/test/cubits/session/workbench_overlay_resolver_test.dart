import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/workbench_overlay_resolver.dart';

void main() {
  test('chat view always renders chat, even while connecting', () {
    expect(
      resolveWorkbenchOverlay(
        phase: SessionPhase.connecting,
        historyStatus: AiHistoryViewStatus.ready,
        view: SessionWorkbenchView.chat,
      ),
      ChatWorkbenchOverlay.chat,
    );
  });

  test('terminal view while connecting shows sessionStarting', () {
    expect(
      resolveWorkbenchOverlay(
        phase: SessionPhase.connecting,
        historyStatus: AiHistoryViewStatus.ready,
        view: SessionWorkbenchView.terminal,
      ),
      ChatWorkbenchOverlay.sessionStarting,
    );
  });

  test('one session error does not affect another session overlay', () {
    expect(
      resolveWorkbenchOverlay(
        phase: SessionPhase.error,
        historyStatus: AiHistoryViewStatus.empty,
        view: SessionWorkbenchView.chat,
      ),
      ChatWorkbenchOverlay.chat, // error is a banner, not an overlay
    );
  });

  test('refreshing history in chat view stays chat', () {
    expect(
      resolveWorkbenchOverlay(
        phase: SessionPhase.running,
        historyStatus: AiHistoryViewStatus.refreshing,
        view: SessionWorkbenchView.chat,
      ),
      ChatWorkbenchOverlay.chat,
    );
  });

  test('running terminal view shows no overlay', () {
    expect(
      resolveWorkbenchOverlay(
        phase: SessionPhase.running,
        historyStatus: AiHistoryViewStatus.ready,
        view: SessionWorkbenchView.terminal,
      ),
      ChatWorkbenchOverlay.none,
    );
  });
}
