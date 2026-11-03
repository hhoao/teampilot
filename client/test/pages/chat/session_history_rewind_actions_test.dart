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
import 'package:teampilot/services/chat/conversation/history/later_checkpoint_messages.dart';

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
                  liveMessages: const [message],
                  builder: (context, binding) {
                    return SessionHistoryThread(
                      runtime: runtime,
                      hasOlder: false,
                      isLoadingOlder: false,
                      checkpointCommits: binding.history.checkpointCommits,
                      checkedOutCommit: binding.history.checkedOutCommit,
                      laterMessages: binding.history.laterMessages,
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

      expect(find.byTooltip('Rewind to here'), findsOneWidget);
      expect(find.byTooltip('Fork from here'), findsOneWidget);

      await tester.tap(find.byTooltip('Rewind to here'));
      await tester.pump();
      expect(cubit.rewindStarts, 1);

      await tester.tap(find.byTooltip('Rewind to here'));
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

  @override
  Future<bool> gitAvailableForRewind() async => true;

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  @override
  Future<SeatRewindHistory> loadSeatRewindHistory({
    required AppSession session,
    required String memberId,
    required List<AiMessage> live,
  }) async {
    return const SeatRewindHistory(
      checkpointCommits: {'m1': 'c-later'},
      checkedOutCommit: 'c-here',
      laterMessages: [],
    );
  }

  @override
  Future<void> rewindSeatTo({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    rewindStarts++;
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
