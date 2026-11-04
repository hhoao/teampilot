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
import 'package:teampilot/services/chat/rewind/seat_branches.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('a user message offers versions and a switch', (tester) async {
    final cubit = _BranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byTooltip('Fork from here'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous version'));
    await tester.pump();
    expect(cubit.switchedTo, ['c-first']);
  });

  testWidgets('a second tap while the switch is in flight is ignored', (
    tester,
  ) async {
    final cubit = _GatedBranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    // Both taps land in one frame, before the disabled bar rebuilds.
    await tester.tap(find.byTooltip('Previous version'));
    await tester.tap(find.byTooltip('Previous version'));
    await tester.pump();
    expect(cubit.switchedTo, hasLength(1));

    cubit.gate.complete();
    await tester.pump();
  });

  testWidgets('a failed switch shows the failure toast', (tester) async {
    final cubit = _FailingBranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    await tester.tap(find.byTooltip('Previous version'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Failed to switch version'), findsOneWidget);

    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('editing a user message sends the new text', (tester) async {
    final cubit = _BranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);
    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(cubit.edits, [('u1', 'edited')]);
    // A successful edit closes the inline editor.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a failed edit keeps the editor open with the typed text', (
    tester,
  ) async {
    final cubit = _FailingEditCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);
    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'edited',
    );
    expect(find.text('Failed to send the edited message'), findsOneWidget);

    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('a failed edit can be retried with the same draft', (
    tester,
  ) async {
    final cubit = _FailingEditCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);
    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    TpToast.dismiss();
    await tester.pump();

    cubit.failing = false;
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(cubit.edits, [('u1', 'edited'), ('u1', 'edited')]);
    expect(find.byType(TextField), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('an assistant message offers no edit action or version counter', (
    tester,
  ) async {
    final cubit = _BranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    final assistant = find.byKey(const ValueKey('a1'));
    expect(
      find.descendant(of: assistant, matching: find.byTooltip('Edit message')),
      findsNothing,
    );
    expect(
      find.descendant(of: assistant, matching: find.textContaining(' / ')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: assistant,
        matching: find.byTooltip('Previous version'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: assistant, matching: find.byTooltip('Next version')),
      findsNothing,
    );
  });

  testWidgets(
    'a single-version user message shows edit but no version control',
    (tester) async {
      final cubit = _SingleVersionCubit();
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      // The user message is the last turn, so its action bar is always visible.
      await _pumpThread(
        tester,
        cubit,
        messages: const [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'only version')],
          ),
        ],
      );

      expect(find.byTooltip('Edit message'), findsOneWidget);
      expect(find.text('1 / 1'), findsNothing);
      expect(find.byTooltip('Previous version'), findsNothing);
      expect(find.byTooltip('Next version'), findsNothing);
    },
  );

  testWidgets('a team session offers no branch controls', (tester) async {
    final cubit = _TeamCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    expect(find.byTooltip('Edit message'), findsNothing);
    expect(find.byTooltip('Fork from here'), findsNothing);
  });

  testWidgets('a checkpoint landing without a new live list shows versions', (
    tester,
  ) async {
    final cubit = _GenerationBranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);
    expect(find.text('2 / 2'), findsNothing);

    cubit.landed = true;
    cubit.debugPublishRewindHistory();
    await pumpUntilSettled(tester);

    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('holdTranscript keeps the old branch until it is released', (
    tester,
  ) async {
    const user = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'original question')],
    );
    const reply = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'answer one')],
    );
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(const [user, reply]);

    Widget build({required bool hold}) => MaterialApp(
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
            hasOlder: false,
            isLoadingOlder: false,
            holdTranscript: hold,
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(hold: true));
    await pumpUntilSettled(tester);
    expect(find.text('answer one'), findsOneWidget);

    // The restore replays the parent branch while the edit is in flight.
    runtime.setMessages(const [user]);
    await tester.pump();
    expect(
      find.text('answer one'),
      findsOneWidget,
      reason: 'the held transcript must not repaint mid-edit',
    );

    await tester.pumpWidget(build(hold: false));
    await pumpUntilSettled(tester);

    expect(find.text('answer one'), findsNothing);
    expect(find.text('original question'), findsOneWidget);
  });
}

/// Pumps the history host around a personal session with one user message and
/// one reply. Task 8 adds `onEditUserMessage` to the thread here.
Future<void> _pumpThread(
  WidgetTester tester,
  ChatCubit cubit, {
  List<AiMessage>? messages,
}) async {
  final runtime = ExternalStoreAiThreadRuntime()
    ..setMessages(
      messages ??
          const [
            AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: 'first version')],
            ),
            AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [AiTextPart(text: 'answer')],
            ),
          ],
    );
  final session = AppSession(sessionId: 's1', workspaceId: 'w1', createdAt: 1);
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
                  branches: binding.branches,
                  onSwitchVersion: binding.onSwitchVersion,
                  onForkFrom: binding.onForkFrom,
                  onEditUserMessage: binding.onEditUserMessage,
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
}

class _BranchCubit extends ChatCubit {
  _BranchCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  final switchedTo = <String>[];
  final edits = <(String, String)>[];

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  @override
  Future<void> editSeatTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
  }) async {
    edits.add((userMessageId, text));
  }

  @override
  Future<SeatBranches> loadSeatBranches({
    required AppSession session,
    required String memberId,
  }) async {
    return const SeatBranches(
      turns: {
        'u1': SeatBranchVersion(
          index: 2,
          count: 2,
          commit: 'c-second',
          siblings: ['c-first', 'c-second'],
        ),
      },
      checkedOutCommit: 'c-second',
    );
  }

  @override
  Future<void> switchSeatVersion({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    switchedTo.add(commit);
  }
}

final class _GatedBranchCubit extends _BranchCubit {
  final gate = Completer<void>();

  @override
  Future<void> switchSeatVersion({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    switchedTo.add(commit);
    await gate.future;
  }
}

final class _FailingBranchCubit extends _BranchCubit {
  @override
  Future<void> switchSeatVersion({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    switchedTo.add(commit);
    throw StateError('switch failed');
  }
}

final class _FailingEditCubit extends _BranchCubit {
  var failing = true;

  @override
  Future<void> editSeatTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
  }) async {
    edits.add((userMessageId, text));
    if (failing) throw StateError('edit failed');
  }
}

final class _SingleVersionCubit extends _BranchCubit {
  @override
  Future<SeatBranches> loadSeatBranches({
    required AppSession session,
    required String memberId,
  }) async {
    return const SeatBranches(
      turns: {
        'u1': SeatBranchVersion(
          index: 1,
          count: 1,
          commit: 'c-only',
          siblings: ['c-only'],
        ),
      },
      checkedOutCommit: 'c-only',
    );
  }
}

final class _GenerationBranchCubit extends _BranchCubit {
  var landed = false;

  @override
  Future<SeatBranches> loadSeatBranches({
    required AppSession session,
    required String memberId,
  }) async {
    if (!landed) return const SeatBranches.empty();
    return super.loadSeatBranches(session: session, memberId: memberId);
  }
}

/// Rewind/fork is personal-session only; this stands in for a team seat.
final class _TeamCubit extends _BranchCubit {
  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => false;
}
