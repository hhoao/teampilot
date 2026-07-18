import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_review_messages.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

Widget _harness({
  required AiHistoryState state,
  required AiThreadRuntime runtime,
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
        child: SessionHistoryReviewMessages(
          state: state,
          runtime: runtime,
          onRetry: () {},
          onLoadOlder: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('softReloadError strip visible on ready without wiping thread', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: 'm1',
          role: AiRole.user,
          parts: [AiTextPart(text: 'kept message')],
        ),
      ]);

    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(
          status: AiHistoryViewStatus.ready,
          totalMessageCount: 1,
          softReloadError: 'parse blew up',
        ),
        runtime: runtime,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kSessionHistorySoftReloadErrorKey), findsOneWidget);
    expect(find.byType(SessionHistoryThread), findsOneWidget);
    expect(find.text('kept message'), findsOneWidget);
    expect(find.textContaining("Couldn't refresh"), findsOneWidget);
  });

  testWidgets('empty status with pending runtime messages shows thread', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: 'pending:abc',
          role: AiRole.user,
          parts: [AiTextPart(text: 'optimistic continue')],
        ),
      ]);

    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(status: AiHistoryViewStatus.empty),
        runtime: runtime,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No prior messages for this member yet.'), findsNothing);
    expect(find.byType(SessionHistoryThread), findsOneWidget);
    expect(find.text('optimistic continue'), findsOneWidget);
  });
}
