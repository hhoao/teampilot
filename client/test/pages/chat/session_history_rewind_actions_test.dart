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
import 'package:teampilot/services/chat/rewind/edit/edit_operation.dart';
import 'package:teampilot/services/chat/rewind/edit/seat_edit_coordinator.dart';
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
    cubit.debugPublishRewindHistory('s1');
    await pumpUntilSettled(tester);

    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('the edited bubble updates in place while the resend runs', (
    tester,
  ) async {
    final cubit = _GatedEditCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    final runtime = await _pumpThread(tester, cubit);

    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('edited'), findsOneWidget);
    // The transaction itself renders nothing under the bubble; only a failure
    // or a stop adds the retry action.
    expect(find.byKey(const ValueKey('chat-edit-retry')), findsNothing);
    expect(
      find.text('answer'),
      findsNothing,
      reason: 'the old reply belongs to the branch being replaced',
    );

    // The restore replays the parent prefix before the new turn exists.
    runtime.setMessages(const []);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('edited'),
      findsOneWidget,
      reason: 'the replayed prefix must not replace the optimistic bubble',
    );

    cubit.finish();
    // The running row animates forever; bounded pumps instead of settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the optimistic bubble yields to the new branch', (tester) async {
    final cubit = _GatedEditCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    final runtime = await _pumpThread(tester, cubit);

    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();

    runtime.setMessages(const [
      AiMessage(
        id: 'u2',
        role: AiRole.user,
        parts: [AiTextPart(text: 'edited')],
      ),
      AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'fresh answer')],
      ),
    ]);
    await tester.pump();
    expect(
      find.text('fresh answer'),
      findsNothing,
      reason: 'the host still holds the transcript',
    );

    cubit.finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('fresh answer'), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);
  });

  testWidgets('a same-text parent message does not land the optimistic edit', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages(const [
        AiMessage(
          id: 'u0',
          role: AiRole.user,
          parts: [AiTextPart(text: 'same')],
        ),
        AiMessage(
          id: 'a0',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'parent answer')],
        ),
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: [AiTextPart(text: 'original')],
        ),
      ]);
    final gate = Completer<void>();
    final editor = _editorFor(_GatedEditRun(gate));
    addTearDown(editor.dispose);
    var landed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
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
              branches: const SeatBranches(
                turns: {
                  'u1': SeatBranchVersion(
                    index: 2,
                    count: 2,
                    commit: 'c1',
                    siblings: ['c0', 'c1'],
                  ),
                },
              ),
              seatEdit: editor,
              onEditUserMessage: (messageId, text, {required reopenEditor}) =>
                  editor.submit(
                    messageId: messageId,
                    memberId: 's1',
                    text: text,
                    reopenEditorOnFailure: reopenEditor,
                  ),
              onOptimisticLanded: () => landed = true,
            ),
          ),
        ),
      ),
    );
    await pumpUntilSettled(tester);

    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'same');
    await tester.tap(find.text('Send'));
    await tester.pump();

    // The restore replays the parent, whose last user message also says
    // "same". It must not be mistaken for the resent prompt.
    runtime.setMessages(const [
      AiMessage(
        id: 'u0',
        role: AiRole.user,
        parts: [AiTextPart(text: 'same')],
      ),
      AiMessage(
        id: 'a0',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'parent answer')],
      ),
    ]);
    await tester.pump();
    expect(landed, isFalse);
    // The optimistic branch still owns the tip; adopting the restored prefix
    // would drop the running row and show only the parent answer.
    expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the optimistic bubble survives a runtime swap', (tester) async {
    const user = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'original')],
    );
    const reply = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'answer')],
    );
    final before = ExternalStoreAiThreadRuntime()
      ..setMessages(const [user, reply]);
    // The restore replays the parent prefix, which predates the edit.
    final restored = ExternalStoreAiThreadRuntime()..setMessages(const []);
    final gate = Completer<void>();
    final editor = _editorFor(_GatedEditRun(gate));
    addTearDown(editor.dispose);

    Widget build(AiThreadRuntime runtime) => MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
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
            // Two versions keep the action bar permanently revealed.
            branches: const SeatBranches(
              turns: {
                'u1': SeatBranchVersion(
                  index: 2,
                  count: 2,
                  commit: 'c1',
                  siblings: ['c0', 'c1'],
                ),
              },
            ),
            seatEdit: editor,
            onEditUserMessage: (messageId, text, {required reopenEditor}) =>
                editor.submit(
                  messageId: messageId,
                  memberId: 's1',
                  text: text,
                  reopenEditorOnFailure: reopenEditor,
                ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(before));
    await pumpUntilSettled(tester);
    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text('edited'), findsOneWidget);

    // The seat runtime is replaced while the restore replays the parent.
    await tester.pumpWidget(build(restored));
    await tester.pump();

    expect(find.text('edited'), findsOneWidget);
    expect(
      find.text('answer'),
      findsNothing,
      reason: 'the replaced runtime must not paint the old branch',
    );

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a failed edit keeps its draft across a runtime swap', (
    tester,
  ) async {
    const user = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'original')],
    );
    const reply = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'answer')],
    );
    final before = ExternalStoreAiThreadRuntime()
      ..setMessages(const [user, reply]);
    final restored = ExternalStoreAiThreadRuntime()..setMessages(const []);
    final gate = Completer<void>();
    final editor = _editorFor(_GatedEditRun(gate, fail: true));
    addTearDown(editor.dispose);

    Widget build(AiThreadRuntime runtime) => MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
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
            branches: const SeatBranches(
              turns: {
                'u1': SeatBranchVersion(
                  index: 2,
                  count: 2,
                  commit: 'c1',
                  siblings: ['c0', 'c1'],
                ),
              },
            ),
            seatEdit: editor,
            onEditUserMessage: (messageId, text, {required reopenEditor}) =>
                editor.submit(
                  messageId: messageId,
                  memberId: 's1',
                  text: text,
                  reopenEditorOnFailure: reopenEditor,
                ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(before));
    await pumpUntilSettled(tester);
    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();

    // Restore swaps the runtime while the send is still pending.
    await tester.pumpWidget(build(restored));
    await tester.pump();
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TextField), findsOneWidget);
    // The optimistic bubble stays mounted behind the editor as a height
    // sizer, so read the draft from the field itself.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'edited');
  });

  testWidgets('a host-owned optimistic edit survives a thread remount', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages(const []);
    final seatEdit = SeatEditCoordinator(
      sessionId: 's1',
      run: _noopRun,
      watchdog: Duration.zero,
    );
    addTearDown(seatEdit.dispose);
    await seatEdit.submit(
      messageId: 'u1',
      memberId: 's1',
      text: 'edited',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
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
              seatEdit: seatEdit,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('edited'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
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
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
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

  testWidgets(
    'a failed edit offers a red retry under the bubble on mobile',
    (tester) async {
      final cubit = _FailingEditCubit();
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      await _pumpThread(tester, cubit, mobile: true);

      await tester.tap(find.text('first version'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('chat-edit-sheet-field')),
        'edited',
      );
      await tester.tap(find.byKey(const ValueKey('chat-edit-sheet-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The sheet is gone and the transaction renders nothing, but the author
      // can still resend the same text from the bubble.
      expect(find.byKey(const ValueKey('chat-edit-sheet-field')), findsNothing);
      final retry = find.byKey(const ValueKey('chat-edit-retry'));
      expect(retry, findsOneWidget);

      cubit.failing = false;
      await tester.tap(retry);
      await tester.pump();

      expect(cubit.edits, [('u1', 'edited'), ('u1', 'edited')]);
      expect(find.byKey(const ValueKey('chat-edit-retry')), findsNothing);

      TpToast.dismiss();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    },
  );
}

/// Pumps the history host around a personal session with one user message and
/// one reply. Task 8 adds `onEditUserMessage` to the thread here.
Future<ExternalStoreAiThreadRuntime> _pumpThread(
  WidgetTester tester,
  ChatCubit cubit, {
  List<AiMessage>? messages,
  bool mobile = false,
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
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
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
                  holdTranscript: binding.holdTranscript,
                  seatEdit: binding.seatEdit,
                  mobilePerformanceMode: mobile,
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
  return runtime;
}

class _BranchCubit extends ChatCubit {
  _BranchCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
        seatEditWatchdog: Duration.zero,
      );

  final switchedTo = <String>[];
  final edits = <(String, String)>[];

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  // The real prime resolves a work-plane context and probes git via a real
  // subprocess, which never settles inside the widget test's fake-async zone.
  // These fakes already bypass the policy, so priming is a no-op here.
  @override
  Future<void> prepareRewindFor(AppSession session, String memberId) async {}

  @override
  Future<void> editSeatTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
    void Function(EditPhase phase)? onPhase,
    bool Function()? aborted,
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
    void Function(EditPhase phase)? onPhase,
    bool Function()? aborted,
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

final class _GatedEditCubit extends _BranchCubit {
  final _gate = Completer<void>();

  void finish() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> editSeatTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
    void Function(EditPhase phase)? onPhase,
    bool Function()? aborted,
  }) async {
    edits.add((userMessageId, text));
    onPhase?.call(EditPhase.delivering);
    await _gate.future;
  }
}

Future<void> _noopRun({
  required String sessionId,
  required String memberId,
  required String userMessageId,
  required String text,
  required void Function(EditPhase phase) onPhase,
  required bool Function() aborted,
}) async {}

final class _GatedEditRun {
  _GatedEditRun(this.gate, {this.fail = false});

  final Completer<void> gate;
  final bool fail;

  Future<void> call({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
    required void Function(EditPhase phase) onPhase,
    required bool Function() aborted,
  }) async {
    onPhase(EditPhase.delivering);
    await gate.future;
    if (fail) throw StateError('edit failed');
  }
}

SeatEditCoordinator _editorFor(_GatedEditRun run) => SeatEditCoordinator(
  sessionId: 's1',
  run: run.call,
  watchdog: Duration.zero,
);
