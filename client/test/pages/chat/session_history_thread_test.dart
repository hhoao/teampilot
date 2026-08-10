import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/history_scroll_cursor_lock.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/widgets/scroll_cursor_lock.dart';
import 'package:tp_markdown/tp_markdown.dart' show ContentDisplayMode, MarkdownDisplayModeScope;

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
  SessionHistoryLiveChrome liveChrome = SessionHistoryLiveChrome.none,
  VoidCallback? onLoadOlder,
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
        child: SessionHistoryThread(
          runtime: runtime,
          hasOlder: hasOlder,
          isLoadingOlder: isLoadingOlder,
          liveChrome: liveChrome,
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

  // SelectionArea must be an *ancestor* of the scrollable so the framework's
  // edge auto-scroll engages while drag-selecting (Scrollable's
  // _ScrollableSelectionContainerDelegate). Sitting inside the scroll content
  // (old flutter/flutter#110917 workaround) disables edge auto-scroll.
  testWidgets(
    'SelectionArea wraps SingleChildScrollView as scroll ancestor',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(5));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      final scrollView = find.byType(SingleChildScrollView);
      expect(scrollView, findsOneWidget);
      expect(
        find.ancestor(
          of: scrollView,
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: scrollView,
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'drag-selecting beyond the top edge auto-scrolls the thread',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(120));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = position.pixels;
      expect(before, greaterThan(100));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SingleChildScrollView)) +
            const Offset(0, -80),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // Hold the drag beyond the top edge of the viewport.
      await gesture.moveTo(const Offset(200, -60));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(position.pixels, lessThan(before));
    },
  );

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
    'sending a message after scrolling up re-sticks to the new tip',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      // User scrolls up to read history → stick released.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();

      var position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.pixels, lessThan(position.maxScrollExtent));

      // User sends a message → user bubble appended to the tip.
      store.setMessages([
        ..._soloUserMessages(20),
        AiMessage(
          id: 'sent',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'hello')],
        ),
      ]);
      await tester.pumpAndSettle();

      position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      // The sent bubble must be visible: the thread re-sticks to the bottom.
      expect(position.pixels, closeTo(position.maxScrollExtent, 2.0));
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
    'scroll suppresses hover effects then resumes cursor lock after idle',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ScrollCursorLock>(
          find.byType(ScrollCursorLock),
        ).active,
        isFalse,
      );

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pump();

      expect(
        tester.widget<ScrollCursorLock>(
          find.byType(ScrollCursorLock),
        ).active,
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();

      expect(
        tester.widget<ScrollCursorLock>(
          find.byType(ScrollCursorLock),
        ).active,
        isFalse,
      );
    },
  );

  testWidgets(
    'running footer visible when liveChrome is running',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(5));

      await tester.pumpWidget(
        _harness(runtime: store, liveChrome: SessionHistoryLiveChrome.running),
      );
      // CircularProgressIndicator animates forever — do not pumpAndSettle.
      await tester.pump();

      expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);
      expect(find.text('Running…'), findsOneWidget);
    },
  );

  testWidgets(
    'starting footer visible when liveChrome is starting',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(5));

      await tester.pumpWidget(
        _harness(runtime: store, liveChrome: SessionHistoryLiveChrome.starting),
      );
      await tester.pump();

      expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);
      expect(find.text('Starting…'), findsOneWidget);
    },
  );

  testWidgets(
    'sync runtime notify while sibling builds does not throw',
    (tester) async {
      // Seat runtime is seat-scoped; sync notify may still fire during sibling
      // deferred mount. A seat reload during one tab's build must not
      // markNeedsBuild a retained SessionHistoryThread under another branch
      // (TpDeferredForegroundMount keep-alive).
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(3));
      var notifyDuringBuild = false;

      Widget tree() {
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 600,
                  height: 300,
                  child: SessionHistoryThread(
                    runtime: store,
                    hasOlder: false,
                    isLoadingOlder: false,
                    onLoadOlder: () {},
                  ),
                ),
                Builder(
                  builder: (context) {
                    if (notifyDuringBuild) {
                      store.setLoading();
                    }
                    return const SizedBox(height: 8);
                  },
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();

      notifyDuringBuild = true;
      await tester.pumpWidget(tree());
      await tester.pump();
    },
  );

  testWidgets(
    'oversized user message collapses to a fade mask and expands',
    (tester) async {
      // A giant single user message (e.g. a bundled-skill paste) must not render
      // in full: SessionHistoryThread provides AiHistoryRenderScope so the
      // budgeted mask collapse kicks in instead of laying out the whole
      // document (which froze open for ~10 s on a 785 KB user message).
      final rows = [
        for (var r = 0; r < 20; r++) '| c$r-a | c$r-b |',
      ].join('\n');
      final markdown = '| A | B |\n| --- | --- |\n$rows';
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages([
          AiMessage(
            id: 'huge',
            role: AiRole.user,
            parts: [AiTextPart(text: markdown)],
          ),
        ]);

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      // Collapsed by default: budgeted preview masked with an expand chevron.
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('c0-a'), findsOneWidget);
      expect(find.text('c19-a'), findsNothing);

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.text('c19-a'), findsOneWidget);
      expect(find.byKey(kMaskCollapseBarKey), findsOneWidget);
    },
  );

  testWidgets('flatten user message via scope renders no mask', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        AiMessage(
          id: 'huge',
          role: AiRole.user,
          parts: [
            AiTextPart(
              text:
                  '| A |\n| --- |\n${List.generate(12, (i) => '| c$i |').join('\n')}',
            ),
          ],
        ),
      ]);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(extensions: [AiMessageTheme.test()]),
        home: Scaffold(
          body: MarkdownDisplayModeScope(
            userMessageMode: ContentDisplayMode.flatten,
            child: SizedBox(
              width: 600,
              height: 400,
              child: SessionHistoryThread(
                runtime: store,
                hasOlder: false,
                isLoadingOlder: false,
                onLoadOlder: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // flatten mode: the user message renders fully — no mask chevron.
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.text('c0'), findsOneWidget);
    expect(find.text('c11'), findsOneWidget);
  });

  testWidgets(
    'jumpTo during layout does not schedule build mid-frame',
    (tester) async {
      // Measure/stick jumps and Scrollable.jumpTo dispatch ScrollStart during
      // layout. Hover suppress must not ValueNotifier→setState mid-frame
      // ("Build scheduled during frame").
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));
      var jumpDuringLayout = false;

      Widget tree() {
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 600,
                  height: 300,
                  child: SessionHistoryThread(
                    runtime: store,
                    hasOlder: false,
                    isLoadingOlder: false,
                    onLoadOlder: () {},
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (jumpDuringLayout) {
                      final state = tester.state<ScrollableState>(
                        find.byType(Scrollable).first,
                      );
                      final pos = state.position;
                      final target = (pos.pixels - 40).clamp(
                        0.0,
                        pos.maxScrollExtent,
                      );
                      if ((pos.pixels - target).abs() > 0.5) {
                        pos.jumpTo(target);
                      }
                    }
                    return const SizedBox(height: 8);
                  },
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();

      // Break stick + let hover resume so suppress path mutates notifier.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();

      jumpDuringLayout = true;
      await tester.pumpWidget(tree());
      await tester.pump();
    },
  );
}
