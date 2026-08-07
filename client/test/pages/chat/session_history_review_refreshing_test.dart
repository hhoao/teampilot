import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_review_messages.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

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

  testWidgets('refreshing renders the thread + slim strip, never full-pane loading', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(const [
        AiMessage(id: 'm-0', role: AiRole.user, parts: [AiTextPart(text: 'hi')]),
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
                onLoadOlder: () {},
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
  });

  testWidgets('error-with-content keeps the thread mounted, not the error pane', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(const [
        AiMessage(id: 'm-0', role: AiRole.user, parts: [AiTextPart(text: 'hi')]),
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
                onLoadOlder: () {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SessionHistoryThread), findsOneWidget);
    expect(find.text("Couldn't load conversation history."), findsNothing);
  });
}
