import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/pages/chat/session_history_review_messages.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/repositories/layout_repository.dart';

Widget _harness({
  required AiHistoryState state,
  required AiThreadRuntime runtime,
  Map<String, FailedMessageStatus> pendingDeliveryStatuses = const {},
  ValueChanged<String>? onRetryFailedMessage,
  ValueChanged<String>? onEditFailedMessage,
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
        child: SessionHistoryReviewMessages(
          state: state,
          runtime: runtime,
          onRetry: () {},
          onLoadOlder: () {},
          pendingDeliveryStatuses: pendingDeliveryStatuses,
          onRetryFailedMessage: onRetryFailedMessage,
          onEditFailedMessage: onEditFailedMessage,
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

  testWidgets('persisted pending bubble renders its delivery status', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: 'pending:failed',
          role: AiRole.user,
          parts: [AiTextPart(text: 'recover me')],
        ),
      ]);

    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(status: AiHistoryViewStatus.ready),
        runtime: runtime,
        pendingDeliveryStatuses: const {
          'pending:failed': FailedMessageStatus.failed,
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('recover me'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('failed bubble exposes retry and edit-and-retry actions', (
    tester,
  ) async {
    String? retryId;
    String? editId;
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: 'pending:failed',
          role: AiRole.user,
          parts: [AiTextPart(text: 'recover me')],
        ),
      ]);

    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(status: AiHistoryViewStatus.ready),
        runtime: runtime,
        pendingDeliveryStatuses: const {
          'pending:failed': FailedMessageStatus.failed,
        },
        onRetryFailedMessage: (id) => retryId = id,
        onEditFailedMessage: (id) => editId = id,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Edit and retry'));

    expect(retryId, 'pending:failed');
    expect(editId, 'pending:failed');
  });

  testWidgets('default prefs fold read but keep subagent standalone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();
    final foldCategories = cubit.state.preferences.foldToolCallCategories;

    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            const AiReasoningPart(text: 'r'),
            // Note: parts are constructed directly without the annotation
            // pipeline — categories must be explicit, otherwise the default
            // `other` breaks the fold predicate (Read would render standalone).
            AiToolCallPart(
              toolCallId: '1',
              toolName: 'Read',
              category: AiToolCallCategory.read,
            ),
            AiToolCallPart(
              toolCallId: '2',
              toolName: 'Task',
              category: AiToolCallCategory.subagent,
            ),
          ],
        ),
      ]);

    // Mirror SessionChatMessageArea's assembly: the scope predicate comes from
    // LayoutCubit preferences (the real wiring lives in the message area's
    // inner Stack, which the harness tree cannot see).
    final child = AiToolCallFoldScope(
      shouldFold: (part) => foldCategories.contains(part.category),
      child: _harness(
        state: const AiHistoryState(
          status: AiHistoryViewStatus.ready,
          totalMessageCount: 1,
        ),
        runtime: runtime,
      ),
    );
    await tester.pumpWidget(BlocProvider.value(value: cubit, child: child));
    await tester.pumpAndSettle();

    // Exactly one chain head (reasoning + Read folded in).
    expect(find.textContaining('Explored 1 file'), findsOneWidget);
    // Task (subagent, not folded) stays standalone and visible.
    expect(find.textContaining('Task'), findsWidgets);
    // Read is hidden inside the folded chain.
    expect(find.textContaining('Read'), findsNothing);
  });
}
