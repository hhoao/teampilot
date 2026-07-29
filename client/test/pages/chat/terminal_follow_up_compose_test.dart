import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/session/history_seat_key.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/follow_up/follow_up_queue_strip.dart';
import 'package:teampilot/widgets/follow_up/terminal_follow_up_compose.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  test('shouldShowTerminalFollowUpStrip only when queue has items', () {
    expect(shouldShowTerminalFollowUpStrip(const FollowUpQueue()), isFalse);
    expect(
      shouldShowTerminalFollowUpStrip(
        const FollowUpQueue(
          items: [FollowUpQueuedMessage(id: '1', content: 'queued')],
        ),
      ),
      isTrue,
    );
  });

  testWidgets('shows strip for shared History seat queue without TextField', (
    tester,
  ) async {
    final store = InMemoryFollowUpQueueStore();
    final chatCubit = ChatCubit(
      executableResolver: () => 'claude',
      automationRepository: testAutomationRepository(),
      followUpQueueStore: store,
    );
    addTearDown(chatCubit.close);

    const sessionId = 'sess-1';
    final seatKey = followUpSeatKey(sessionId, sessionId);
    store.enqueue(seatKey, 'from history');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ThemeData(useMaterial3: true).colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: BlocProvider<ChatCubit>.value(
            value: chatCubit,
            child: Scaffold(
              body: TerminalFollowUpCompose(
                session: AppSession(
                  sessionId: sessionId,
                  workspaceId: 'ws-1',
                  folders: const [],
                  createdAt: 0,
                ),
                selectedMemberId: '',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kTerminalFollowUpComposeKey), findsOneWidget);
    expect(find.byKey(kSessionFollowUpQueueStripKey), findsOneWidget);
    expect(find.text('from history'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('hides when queue empty even if member would be working', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<ChatCubit>.value(
          value: chatCubit,
          child: TerminalFollowUpCompose(
            session: AppSession(
              sessionId: 'sess-1',
              workspaceId: 'ws-1',
              folders: const [],
              createdAt: 0,
            ),
            selectedMemberId: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kTerminalFollowUpComposeKey), findsNothing);
  });
}
