import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/services/chat/rewind/seat_branches.dart';

List<AiMessage> _users(int count) => List.generate(
  count,
  (i) => AiMessage(
    id: 'm$i',
    role: AiRole.user,
    parts: [AiTextPart(text: 'msg $i')],
  ),
);

/// Live assistant tip: reasoning tail while thinking, prose tail once the
/// answer starts (which folds the thinking body away).
class _Tip {
  String reasoning = List.generate(40, (i) => 'line $i').join('\n');
  String prose = '';

  List<AiMessage> get messages => [
    ..._users(15),
    AiMessage(
      id: 'tip',
      role: AiRole.assistant,
      parts: [
        AiReasoningPart(text: reasoning),
        if (prose.isNotEmpty) AiTextPart(text: prose),
      ],
    ),
  ];
}

final Finder _thinkingScrollable = find.descendant(
  of: find.byType(AiReasoningPartView),
  matching: find.byType(Scrollable),
);

Future<ExternalStoreAiThreadRuntime> _pumpLiveTip(
  WidgetTester tester,
  _Tip tip,
) async {
  final store = ExternalStoreAiThreadRuntime()..setMessages(tip.messages);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(
        extensions: [AiMessageTheme.test(cotExpandLatestOnOpen: true)],
      ),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 600,
          child: SessionHistoryThread(
            runtime: store,
            hasOlder: false,
            isLoadingOlder: false,
            liveChrome: SessionHistoryLiveChrome.running,
            branches: const SeatBranches.empty(),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return store;
}

Future<void> _pushTail(
  WidgetTester tester,
  ExternalStoreAiThreadRuntime store,
  _Tip tip,
) async {
  store.setMessages(tip.messages);
  // Three frames: one to lay the new tail out, one for the stick chain's
  // post-frame jump, one for the follow to land on the settled extent.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

ScrollPosition _outer(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

ScrollPosition _thinking(WidgetTester tester) =>
    tester.state<ScrollableState>(_thinkingScrollable.first).position;

void main() {
  testWidgets('thinking follow inside the real transcript', (tester) async {
    final tip = _Tip();
    final store = await _pumpLiveTip(tester, tip);

    expect(
      _thinking(tester).maxScrollExtent - _thinking(tester).pixels,
      lessThan(4.0),
      reason: 'mount must pin the live thinking body to the newest line',
    );

    final rect = tester.getRect(_thinkingScrollable.first);
    await tester.dragFrom(rect.center, const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 50));
    final readOffset = _thinking(tester).pixels;

    tip.reasoning = '${tip.reasoning}\nwhile reading';
    await _pushTail(tester, store, tip);
    expect(
      _thinking(tester).pixels,
      closeTo(readOffset, 1.0),
      reason: 'the live turn must not yank a reader back to the newest line',
    );

    await tester.dragFrom(rect.center, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 50));

    tip.reasoning = '${tip.reasoning}\nafter return';
    await _pushTail(tester, store, tip);
    expect(
      _thinking(tester).maxScrollExtent - _thinking(tester).pixels,
      lessThan(4.0),
      reason: 'returning to the newest line must resume the follow',
    );
  });

  testWidgets('a streamed chunk does not re-create the live scroll positions', (
    tester,
  ) async {
    final tip = _Tip();
    final store = await _pumpLiveTip(tester, tip);

    final before = _thinking(tester);
    tip.reasoning = '${tip.reasoning}\nchunk';
    await _pushTail(tester, store, tip);

    // A fresh ThemeData per chunk makes Scrollable.didChangeDependencies call
    // _updatePosition: every descendant ScrollPosition is thrown away (which
    // also cancels in-flight scroll activities) on every streamed chunk.
    expect(
      identical(before, _thinking(tester)),
      isTrue,
      reason: 'the live tip theme must be reused across streamed chunks',
    );
  });

  testWidgets('the transcript keeps following after the thinking body folds', (
    tester,
  ) async {
    final tip = _Tip();
    final store = await _pumpLiveTip(tester, tip);

    expect(
      _outer(tester).maxScrollExtent - _outer(tester).pixels,
      lessThan(2.0),
      reason: 'the transcript follows the live tip while thinking',
    );

    // Prose starts: the tail is no longer a thinking chain, so the body folds
    // back to its summary row and the transcript shrinks by ~256px.
    tip.prose = 'answer';
    await _pushTail(tester, store, tip);
    await tester.pump(const Duration(milliseconds: 300));

    for (var i = 0; i < 5; i++) {
      tip.prose = '${tip.prose}\nmore $i';
      await _pushTail(tester, store, tip);
      expect(
        _outer(tester).maxScrollExtent - _outer(tester).pixels,
        lessThan(2.0),
        reason: 'folding the thinking body must not cancel the follow',
      );
    }
  });
}
