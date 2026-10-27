import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

List<AiMessage> _messages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'msg $i')],
    ),
  );
}

/// Mirrors how the workbench stacks open sessions: every host stays mounted,
/// and the one that is not in front is wrapped in [TpKeepAliveLayer] +
/// `TickerMode(enabled: false)` (see `KeepAliveSessionStack`).
Widget _harness({
  required AiThreadRuntime runtime,
  required bool active,
  SessionHistoryLiveChrome liveChrome = SessionHistoryLiveChrome.none,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(extensions: [AiMessageTheme.test()]),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: TpKeepAliveLayer(
          active: active,
          child: TickerMode(
            enabled: active,
            child: SessionHistoryThread(
              runtime: runtime,
              hasOlder: false,
              isLoadingOlder: false,
              liveChrome: liveChrome,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Fixed-frame pump: the thread's stuck-to-end chain and the viewport's
/// chunked fill both run off post-frame callbacks, so `pumpAndSettle` can
/// stall (a bare chain does not schedule frames by itself).
Future<void> _pumpFrames(WidgetTester tester, {int frames = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ScrollPosition _position(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable).first).position;
}

void main() {
  testWidgets('backgrounded thread re-sticks to the tip when the tab returns', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages(_messages(40));
    await tester.pumpWidget(_harness(runtime: runtime, active: true));
    await _pumpFrames(tester);
    expect(
      _position(tester).pixels,
      closeTo(_position(tester).maxScrollExtent, 2),
    );

    // Leave the tab: the host stays mounted but is not foreground.
    await tester.pumpWidget(_harness(runtime: runtime, active: false));
    await _pumpFrames(tester);

    // The turn finished while away — no further runtime event will arrive
    // after the return, so the foreground handoff itself must re-anchor.
    runtime.setMessages(_messages(90));
    await _pumpFrames(tester);

    await tester.pumpWidget(_harness(runtime: runtime, active: true));
    await _pumpFrames(tester);

    final position = _position(tester);
    expect(
      position.pixels,
      closeTo(position.maxScrollExtent, 2),
      reason: 'returning to a followed thread must show the new tip',
    );
  });

  testWidgets('backgrounded live turn keeps following after the return', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages(_messages(40));
    await tester.pumpWidget(
      _harness(
        runtime: runtime,
        active: true,
        liveChrome: SessionHistoryLiveChrome.running,
      ),
    );
    await _pumpFrames(tester);

    await tester.pumpWidget(
      _harness(
        runtime: runtime,
        active: false,
        liveChrome: SessionHistoryLiveChrome.running,
      ),
    );
    await _pumpFrames(tester);
    runtime.setMessages(_messages(90));
    await _pumpFrames(tester);

    await tester.pumpWidget(
      _harness(
        runtime: runtime,
        active: true,
        liveChrome: SessionHistoryLiveChrome.running,
      ),
    );
    await _pumpFrames(tester, frames: 5);

    expect(
      _position(tester).pixels,
      closeTo(_position(tester).maxScrollExtent, 2),
      reason: 'a live turn must re-attach to the tip on reactivation',
    );

    // Streaming continues: growth must keep being followed, not just the
    // one-time catch-up jump.
    runtime.setMessages(_messages(120));
    await _pumpFrames(tester, frames: 5);
    expect(
      _position(tester).pixels,
      closeTo(_position(tester).maxScrollExtent, 2),
    );
  });

  testWidgets('backgrounded thread scrolled up keeps its reading position', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages(_messages(40));
    await tester.pumpWidget(_harness(runtime: runtime, active: true));
    await _pumpFrames(tester);

    // Read history: stick releases.
    _position(tester).jumpTo(1200);
    await tester.pump();

    await tester.pumpWidget(_harness(runtime: runtime, active: false));
    await _pumpFrames(tester);
    runtime.setMessages(_messages(90));
    await _pumpFrames(tester);

    await tester.pumpWidget(_harness(runtime: runtime, active: true));
    await _pumpFrames(tester);

    final position = _position(tester);
    expect(
      position.pixels,
      closeTo(1200, 2),
      reason: 'returning to a scrolled-up thread must not yank to the tip',
    );
    expect(position.maxScrollExtent - position.pixels, greaterThan(2));
  });

  testWidgets('returning to an unchanged thread leaves the offset alone', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages(_messages(40));
    await tester.pumpWidget(_harness(runtime: runtime, active: true));
    await _pumpFrames(tester);
    final before = _position(tester).pixels;

    await tester.pumpWidget(_harness(runtime: runtime, active: false));
    await _pumpFrames(tester);
    await tester.pumpWidget(_harness(runtime: runtime, active: true));
    await _pumpFrames(tester);

    expect(_position(tester).pixels, closeTo(before, 2));
  });
}
