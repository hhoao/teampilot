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
import 'package:teampilot/widgets/follow_up/terminal_follow_up_compose.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  test('shouldShowTerminalFollowUpCompose hides when idle and empty', () {
    expect(
      shouldShowTerminalFollowUpCompose(
        memberWorking: false,
        queue: const FollowUpQueue(),
      ),
      isFalse,
    );
    expect(
      shouldShowTerminalFollowUpCompose(
        memberWorking: true,
        queue: const FollowUpQueue(),
      ),
      isTrue,
    );
    expect(
      shouldShowTerminalFollowUpCompose(
        memberWorking: false,
        queue: const FollowUpQueue(
          items: [FollowUpQueuedMessage(id: '1', content: 'queued')],
        ),
      ),
      isTrue,
    );
  });

  testWidgets('working submit enqueues into shared History seat key', (
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
    const shellMemberId = sessionId;
    final seatKey = followUpSeatKey(sessionId, shellMemberId);
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: 'ws-1',
      folders: const [],
      createdAt: 0,
    );

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
                session: session,
                selectedMemberId: '',
                memberWorking: true,
                supportsTurnInterrupt: true,
                permissionWaiting: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kTerminalFollowUpComposeKey), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'terminal follow up');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    final queue = store.queueFor(seatKey);
    expect(queue.items, hasLength(1));
    expect(queue.items.single.content, 'terminal follow up');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('hides compose bar when idle and queue empty', (tester) async {
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
            memberWorking: false,
            supportsTurnInterrupt: true,
            permissionWaiting: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kTerminalFollowUpComposeKey), findsNothing);
  });
}
