import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/chat/session_history_rewind_host.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_history.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'rewind and fork disable while a rewind is running, and a failure is shown',
    (tester) async {
      final cubit = _FakeRewindCubit();
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      const message = AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'live one')],
      );
      final runtime = ExternalStoreAiThreadRuntime()..setMessages([message]);
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
      );
      final workspace = Workspace(workspaceId: 'w1', createdAt: 1);

      await tester.pumpWidget(
        BlocProvider<ChatCubit>.value(
          value: cubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: ThemeData(extensions: [AiMessageTheme.test()]),
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: SessionHistoryRewindHost(
                  session: session,
                  workspace: workspace,
                  memberId: session.sessionId,
                  builder: (context, binding) {
                    return SessionHistoryThread(
                      runtime: runtime,
                      hasOlder: false,
                      isLoadingOlder: false,
                      checkpointCommits: binding.history.checkpointCommits,
                      orderedCommits: binding.history.orderedCommits,
                      checkedOutCommit: binding.history.checkedOutCommit,
                      onRewindTo: binding.onRewindTo,
                      onForkFrom: binding.onForkFrom,
                      turnInFlight: binding.busy,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntilSettled(tester);

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byTooltip('Next version'), findsOneWidget);
      expect(find.byTooltip('Fork from here'), findsOneWidget);

      // Two taps in one frame: the bar is still enabled when the second one
      // lands, so the host itself has to stay single-flight.
      await tester.tap(find.byTooltip('Next version'));
      await tester.tap(find.byTooltip('Next version'));
      await tester.pump();
      expect(cubit.rewindStarts, 1);
      expect(cubit.rewindCommits, ['c-later']);

      await tester.tap(find.byTooltip('Next version'));
      await tester.tap(find.byTooltip('Fork from here'));
      await tester.pump();
      expect(cubit.rewindStarts, 1);
      expect(cubit.forkStarts, 0);

      cubit.rewindGate.completeError(StateError('restore failed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Failed to rewind conversation'), findsOneWidget);
      TpToast.dismiss();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    },
  );

  testWidgets(
    'checkpoint generation shows rewind actions without a new live list',
    (tester) async {
      final cubit = _GenerationCubit();
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      const message = AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'live one')],
      );
      final runtime = ExternalStoreAiThreadRuntime()..setMessages([message]);
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
      );
      final workspace = Workspace(workspaceId: 'w1', createdAt: 1);

      await tester.pumpWidget(
        BlocProvider<ChatCubit>.value(
          value: cubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: ThemeData(extensions: [AiMessageTheme.test()]),
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: SessionHistoryRewindHost(
                  session: session,
                  workspace: workspace,
                  memberId: session.sessionId,
                  builder: (context, binding) {
                    return SessionHistoryThread(
                      runtime: runtime,
                      hasOlder: false,
                      isLoadingOlder: false,
                      checkpointCommits: binding.history.checkpointCommits,
                      orderedCommits: binding.history.orderedCommits,
                      checkedOutCommit: binding.history.checkedOutCommit,
                      onRewindTo: binding.onRewindTo,
                      onForkFrom: binding.onForkFrom,
                      turnInFlight: binding.busy,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntilSettled(tester);
      expect(find.byTooltip('Fork from here'), findsNothing);
      expect(cubit.state.rewindHistoryGeneration, 0);

      cubit.landed = true;
      cubit.debugPublishRewindHistory();
      expect(cubit.state.rewindHistoryGeneration, 1);
      await tester.pump();
      await tester.pump();
      await pumpUntilSettled(tester);

      expect(find.byTooltip('Fork from here'), findsOneWidget);
      expect(find.byTooltip('Previous version'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
    },
  );

  testWidgets('the version control sits on the checked-out checkpoint only', (
    tester,
  ) async {
    final cubit = _StaticHistoryCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    const first = AiMessage(
      id: 'm1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'first')],
    );
    const last = AiMessage(
      id: 'm2',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'second')],
    );
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(const [first, last]);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'w1', createdAt: 1);

    await tester.pumpWidget(
      BlocProvider<ChatCubit>.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: SessionHistoryRewindHost(
                session: session,
                workspace: workspace,
                memberId: session.sessionId,
                builder: (context, binding) {
                  return SessionHistoryThread(
                    runtime: runtime,
                    hasOlder: false,
                    isLoadingOlder: false,
                    checkpointCommits: binding.history.checkpointCommits,
                    orderedCommits: binding.history.orderedCommits,
                    checkedOutCommit: binding.history.checkedOutCommit,
                    onRewindTo: binding.onRewindTo,
                    onForkFrom: binding.onForkFrom,
                    turnInFlight: binding.busy,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await pumpUntilSettled(tester);

    // Only the message that closed the checked-out turn carries the control.
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('1 / 2'), findsNothing);
    expect(find.byTooltip('Fork from here'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous version'));
    await tester.pump();
    expect(cubit.rewindCommits, ['c1']);
  });
}

final class _StaticHistoryCubit extends ChatCubit {
  _StaticHistoryCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  final rewindCommits = <String>[];

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  @override
  Future<SeatRewindHistory> loadSeatRewindHistory({
    required AppSession session,
    required String memberId,
  }) async {
    return const SeatRewindHistory(
      checkpointCommits: {'m1': 'c1', 'm2': 'c2'},
      orderedCommits: ['c1', 'c2'],
      checkedOutCommit: 'c2',
    );
  }

  @override
  Future<void> rewindSeatTo({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    rewindCommits.add(commit);
  }
}

final class _GenerationCubit extends ChatCubit {
  _GenerationCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  var landed = false;

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  @override
  Future<SeatRewindHistory> loadSeatRewindHistory({
    required AppSession session,
    required String memberId,
  }) async {
    if (!landed) return const SeatRewindHistory.empty();
    return const SeatRewindHistory(
      checkpointCommits: {'m1': 'c1'},
      orderedCommits: ['c0', 'c1'],
      checkedOutCommit: 'c1',
    );
  }
}

final class _FakeRewindCubit extends ChatCubit {
  _FakeRewindCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  final rewindGate = Completer<void>();
  var rewindStarts = 0;
  var forkStarts = 0;
  final rewindCommits = <String>[];

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  @override
  Future<SeatRewindHistory> loadSeatRewindHistory({
    required AppSession session,
    required String memberId,
  }) async {
    return const SeatRewindHistory(
      checkpointCommits: {'m1': 'c-here'},
      orderedCommits: ['c-here', 'c-later'],
      checkedOutCommit: 'c-here',
    );
  }

  @override
  Future<void> rewindSeatTo({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    rewindStarts++;
    rewindCommits.add(commit);
    await rewindGate.future;
  }

  @override
  Future<AppSession?> forkSeatFrom({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    forkStarts++;
    return null;
  }
}
