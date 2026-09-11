import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

import '../support/post_frame_test_harness.dart';

List<AiMessage> _threadMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'msg $i')],
    ),
  );
}

/// Pumps the transcript host (the widget owning the thread scroll
/// controller) against a [ChatCubit]'s anchor map, like the chat workbench
/// does. A group move remounts this host; domain state (cubits/registries)
/// survives, only the scroll position needs restoring.
Widget _host({required ChatCubit chat, required AiThreadRuntime runtime}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(extensions: [AiMessageTheme.test()]),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: SessionHistoryThread(
          runtime: runtime,
          hasOlder: false,
          isLoadingOlder: false,
          scrollAnchorKey: 's1',
          scrollAnchors: chat.sessionScrollAnchors,
        ),
      ),
    ),
  );
}

/// Fixed-frame pump: the thread chunk-fills its data window and the anchor
/// restore ticks over post-frame callbacks, so settle-style waits can stall
/// (a bare post-frame chain does not schedule a frame). Enough frames for
/// the fill, all turn measurements, and the bounded restore window (24) to
/// finish.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 60}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ScrollPosition _position(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable).first).position;
}

void main() {
  testWidgets('seeded anchor restores the reading position on mount', (
    tester,
  ) async {
    final chat = testChatCubit(executableResolver: () => 'true');
    addTearDown(chat.close);
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(_threadMessages(40));
    chat.sessionScrollAnchors['s1'] = 200;

    await tester.pumpWidget(_host(chat: chat, runtime: runtime));
    await _pumpFrames(tester);

    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThanOrEqualTo(200));
    expect(position.pixels, 200);
  });

  testWidgets('anchor written on dispose restores after remount', (
    tester,
  ) async {
    final chat = testChatCubit(executableResolver: () => 'true');
    addTearDown(chat.close);
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(_threadMessages(40));

    // Mount without an anchor — default open-at-end behavior.
    await tester.pumpWidget(_host(chat: chat, runtime: runtime));
    await _pumpFrames(tester);
    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThan(200));
    expect(chat.sessionScrollAnchors.containsKey('s1'), isFalse);

    // User scrolls up to read mid-thread, then the host unmounts (e.g. the
    // tab moves to another split group).
    position.jumpTo(200);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(chat.sessionScrollAnchors['s1'], 200);

    // Remount in the new group — the reading position comes back.
    await tester.pumpWidget(_host(chat: chat, runtime: runtime));
    await _pumpFrames(tester);
    expect(_position(tester).pixels, 200);
  });

  testWidgets('without an anchor the default open-at-end behavior stays', (
    tester,
  ) async {
    final chat = testChatCubit(executableResolver: () => 'true');
    addTearDown(chat.close);
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(_threadMessages(40));

    await tester.pumpWidget(_host(chat: chat, runtime: runtime));
    await _pumpFrames(tester);

    final position = _position(tester);
    expect(chat.sessionScrollAnchors, isEmpty);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('anchor beyond maxScrollExtent clamps to maxScrollExtent', (
    tester,
  ) async {
    final chat = testChatCubit(executableResolver: () => 'true');
    addTearDown(chat.close);
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(_threadMessages(10));
    chat.sessionScrollAnchors['s1'] = (1 << 30).toDouble();

    await tester.pumpWidget(_host(chat: chat, runtime: runtime));
    await _pumpFrames(tester);

    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.maxScrollExtent, lessThan(1 << 30));
    expect(position.pixels, position.maxScrollExtent);
  });
}
