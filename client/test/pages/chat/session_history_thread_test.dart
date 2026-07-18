import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

List<AiMessage> _soloUserMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'msg $i')],
    ),
  );
}

Widget _harness({
  required AiThreadRuntime runtime,
  bool hasOlder = false,
  bool isLoadingOlder = false,
  bool liveRefreshActive = false,
  VoidCallback? onLoadOlder,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(extensions: const [AiMessageTheme()]),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: SessionHistoryThread(
          runtime: runtime,
          hasOlder: hasOlder,
          isLoadingOlder: isLoadingOlder,
          liveRefreshActive: liveRefreshActive,
          onLoadOlder: onLoadOlder,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('SessionHistoryThread builds SelectionArea and VirtualThreadViewport', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(5));

    await tester.pumpWidget(_harness(runtime: store));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.byType(VirtualThreadViewport), findsOneWidget);
  });

  testWidgets(
    'SessionHistoryThread with hasOlder exposes viewport header and load-older',
    (tester) async {
      var loadOlderCalls = 0;
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(40));

      await tester.pumpWidget(
        _harness(
          runtime: store,
          hasOlder: true,
          onLoadOlder: () => loadOlderCalls++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VirtualThreadViewport), findsOneWidget);

      // Break stick-to-end, then drag toward the top until load-older fires.
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, 80));
      await tester.pumpAndSettle();

      for (var i = 0; i < 40 && loadOlderCalls == 0; i++) {
        await tester.drag(scrollable, const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(loadOlderCalls, greaterThan(0));
    },
  );

  testWidgets(
    'scroll-up rebuilds viewport with suppressMeasureScrollCorrection false',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      final before = tester.widget<VirtualThreadViewport>(
        find.byType(VirtualThreadViewport),
      );
      expect(before.suppressMeasureScrollCorrection, isTrue);
      expect(before.retainMountedTurns, isTrue);
      expect(before.fillDataWindow, isTrue);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();

      final after = tester.widget<VirtualThreadViewport>(
        find.byType(VirtualThreadViewport),
      );
      expect(after.suppressMeasureScrollCorrection, isFalse);
    },
  );

  testWidgets(
    'when stick paused and messages grow, new-messages chip appears',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsNothing);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsNothing);

      store.setMessages([
        ..._soloUserMessages(20),
        AiMessage(
          id: 'm20',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'new tip')],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsOneWidget);
      expect(find.text('New messages'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping new-messages chip scrolls to tip and resumes stick',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();

      store.setMessages([
        ..._soloUserMessages(20),
        AiMessage(
          id: 'm20',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'new tip')],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsOneWidget);

      await tester.tap(find.byKey(kSessionHistoryNewMessagesChipKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsNothing);

      final viewport = tester.widget<VirtualThreadViewport>(
        find.byType(VirtualThreadViewport),
      );
      expect(viewport.suppressMeasureScrollCorrection, isTrue);

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 2.0));
    },
  );

  testWidgets(
    'scrolling to tip dismisses new-messages chip and resumes stick',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();

      store.setMessages([
        ..._soloUserMessages(20),
        AiMessage(
          id: 'm20',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'new tip')],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsOneWidget);

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryNewMessagesChipKey), findsNothing);

      final viewport = tester.widget<VirtualThreadViewport>(
        find.byType(VirtualThreadViewport),
      );
      expect(viewport.suppressMeasureScrollCorrection, isTrue);
    },
  );

  testWidgets(
    'running footer visible when liveRefreshActive',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(5));

      await tester.pumpWidget(
        _harness(runtime: store, liveRefreshActive: true),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);
      expect(find.text('Running…'), findsOneWidget);
    },
  );
}
