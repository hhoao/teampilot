import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_review_messages.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/services/chat/rewind/seat_branches.dart';

void main() {
  Widget wrap(Widget child) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    return MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
          child: child,
        ),
      ),
    );
  }

  testWidgets(
    'refreshing renders the thread + slim strip, never full-pane loading',
    (tester) async {
      final runtime = ExternalStoreAiThreadRuntime()
        ..setMessages(const [
          AiMessage(
            id: 'm-0',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hi')],
          ),
        ]);
      final state = AiHistoryState(
        status: AiHistoryViewStatus.refreshing,
        totalMessageCount: 1,
        sessionId: 'sess-a',
        memberId: '',
      );

      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              Expanded(
                child: SessionHistoryReviewMessages(
                  state: state,
                  runtime: runtime,
                  onRetry: () {},
                  onLoadOlder: () async {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Loading conversation history…'),
        findsNothing,
        reason: 'refreshing must not show the full-pane history loading',
      );
      expect(find.byType(SessionHistoryThread), findsOneWidget);
      expect(find.text('Refreshing conversation…'), findsOneWidget);
    },
  );

  // Rewinding a user message reconnects the seat, which briefly drives the
  // history status to `loading` with an empty runtime. The thread must stay
  // mounted through that window (otherwise it is torn down and remounted once
  // per reload — the visible double flash on edit submit).
  testWidgets(
    'an in-flight edit keeps the thread across a loading/empty reload',
    (tester) async {
      final runtime = ExternalStoreAiThreadRuntime()
        ..setMessages(const [
          AiMessage(
            id: 'm-0',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hi')],
          ),
        ]);

      Widget build(AiHistoryState state, {PendingBranchEdit? edit}) => wrap(
        Column(
          children: [
            Expanded(
              child: SessionHistoryReviewMessages(
                state: state,
                runtime: runtime,
                onRetry: () {},
                onLoadOlder: () async {},
                optimisticEdit: edit,
              ),
            ),
          ],
        ),
      );

      const edit = PendingBranchEdit(messageId: 'm-0', text: 'edited');

      await tester.pumpWidget(
        build(
          const AiHistoryState(
            status: AiHistoryViewStatus.ready,
            totalMessageCount: 1,
          ),
          edit: edit,
        ),
      );
      await tester.pump();
      final firstElement = tester.element(find.byType(SessionHistoryThread));
      expect(find.byType(SessionHistoryThread), findsOneWidget);

      // Reconnect: status loading, runtime emptied. Without the edit window
      // guard, _showThread turns false and swaps the thread for the pane.
      runtime.setMessages(const []);
      await tester.pumpWidget(
        build(
          const AiHistoryState(status: AiHistoryViewStatus.loading),
          edit: edit,
        ),
      );
      await tester.pump();

      expect(
        find.byType(SessionHistoryThread),
        findsOneWidget,
        reason: 'the thread must not be swapped for the loading pane mid-edit',
      );
      expect(
        tester.element(find.byType(SessionHistoryThread)),
        same(firstElement),
        reason: 'the thread State must survive the reload, not remount',
      );
    },
  );

  // Inserting/removing the refreshing strip must not shift the Expanded into a
  // different slot and rebuild the whole thread State.
  testWidgets('refreshing strip toggle keeps the same thread State', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(const [
        AiMessage(
          id: 'm-0',
          role: AiRole.user,
          parts: [AiTextPart(text: 'hi')],
        ),
      ]);

    Widget build(AiHistoryViewStatus status) => wrap(
      Column(
        children: [
          Expanded(
            child: SessionHistoryReviewMessages(
              state: AiHistoryState(status: status, totalMessageCount: 1),
              runtime: runtime,
              onRetry: () {},
              onLoadOlder: () async {},
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(build(AiHistoryViewStatus.ready));
    await tester.pump();
    final firstElement = tester.element(find.byType(SessionHistoryThread));

    await tester.pumpWidget(build(AiHistoryViewStatus.refreshing));
    await tester.pump();
    expect(find.text('Refreshing conversation…'), findsOneWidget);
    expect(
      tester.element(find.byType(SessionHistoryThread)),
      same(firstElement),
      reason: 'inserting the strip must not remount the thread',
    );

    await tester.pumpWidget(build(AiHistoryViewStatus.ready));
    await tester.pump();
    expect(
      tester.element(find.byType(SessionHistoryThread)),
      same(firstElement),
      reason: 'removing the strip must not remount the thread',
    );
  });

  testWidgets(
    'error-with-content keeps the thread mounted, not the error pane',
    (tester) async {
      final runtime = ExternalStoreAiThreadRuntime()
        ..setMessages(const [
          AiMessage(
            id: 'm-0',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hi')],
          ),
        ]);
      final state = AiHistoryState(
        status: AiHistoryViewStatus.error,
        errorMessage: 'boom',
        totalMessageCount: 1,
        sessionId: 'sess-a',
        memberId: '',
      );

      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              Expanded(
                child: SessionHistoryReviewMessages(
                  state: state,
                  runtime: runtime,
                  onRetry: () {},
                  onLoadOlder: () async {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SessionHistoryThread), findsOneWidget);
      expect(find.text("Couldn't load conversation history."), findsNothing);
    },
  );
}
