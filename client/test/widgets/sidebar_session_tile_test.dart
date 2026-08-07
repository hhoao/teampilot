import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/automation_state.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/session_working_spinner.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../support/post_frame_test_harness.dart';

final _session = AppSession(
  sessionId: 'sess-1',
  workspaceId: 'ws1',
  createdAt: 1,
  updatedAt: 1,
);

Automation _sessionAutomation() {
  return Automation(
    id: 'auto-1',
    name: 'Ping',
    action: AutomationAction.scheduledMessage,
    workspaceId: 'ws1',
    sessionId: 'sess-1',
    message: 'hello',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final workbenchViews = <(String, SessionWorkbenchView)>[];
  final selectedMembers = <String>[];
  final activeSessionAtSelectMember = <String?>[];
  final eventOrder = <String>[];

  @override
  void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
    eventOrder.add('workbench:$sessionId');
    workbenchViews.add((sessionId, view));
    super.setSessionWorkbenchView(sessionId, view);
  }

  @override
  void selectMember(String memberId) {
    eventOrder.add('selectMember:$memberId');
    activeSessionAtSelectMember.add(state.activeSessionId);
    selectedMembers.add(memberId);
    super.selectMember(memberId);
  }
}

Widget _host({
  required ChatCubit chatCubit,
  required AutomationCubit automationCubit,
  required SessionRepository sessionRepository,
  required AgentAttentionCubit attentionCubit,
  Widget? child,
  FutureOr<void> Function()? onTap,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SessionRepository>.value(value: sessionRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatCubit>.value(value: chatCubit),
          BlocProvider<AutomationCubit>.value(value: automationCubit),
          BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
        ],
        child: Scaffold(
          body:
              child ??
              SidebarSessionTile(
                session: _session,
                onTap: onTap ?? () {},
              ),
        ),
      ),
    ),
  );
}

(AgentAttentionCubit, AutomationCubit) _tileCubits() {
  final attention = AgentAttentionCubit(pruneInterval: null);
  final automation = testAutomationCubit();
  return (attention, automation);
}

Future<void> _openContextMenu(WidgetTester tester) async {
  await tester.tap(
    find.byType(SidebarSessionTile),
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _dismissContextMenu(WidgetTester tester) async {
  // Tap the modal barrier to close the popup menu overlay.
  await tester.tapAt(const Offset(1, 1));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'title Text follows ChatCubit SessionRowContent even if widget.session is stale',
    (tester) async {
      final chatCubit = testChatCubit(executableResolver: () => 'claude');
      final (attention, automationCubit) = _tileCubits();
      addTearDown(chatCubit.close);
      addTearDown(automationCubit.close);
      addTearDown(attention.close);

      final stale = AppSession(
        sessionId: 'sess-1',
        workspaceId: 'ws1',
        display: 'StaleTitle',
        createdAt: 1,
        updatedAt: 1,
      );
      chatCubit.applyState(
        chatCubit.state.copyWith(
          sessions: [
            stale.copyWith(display: 'LiveTitle'),
          ],
        ),
      );

      await tester.pumpWidget(
        _host(
          chatCubit: chatCubit,
          automationCubit: automationCubit,
          attentionCubit: attention,
          sessionRepository: SessionRepository(),
          child: SidebarSessionTile(
            session: stale,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('LiveTitle'), findsOneWidget);
      expect(find.text('StaleTitle'), findsNothing);

      chatCubit.applyState(
        chatCubit.state.copyWith(
          sessions: [
            stale.copyWith(display: 'RenamedTitle'),
          ],
          stateVersion: chatCubit.state.stateVersion + 1,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('RenamedTitle'), findsOneWidget);
      expect(find.text('LiveTitle'), findsNothing);
    },
  );

  testWidgets('pinned session shows trailing push_pin when idle', (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    final pinned = AppSession(
      sessionId: 'sess-pinned',
      workspaceId: 'ws1',
      createdAt: 1,
      updatedAt: 1,
      pinned: true,
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
        child: SidebarSessionTile(
          session: pinned,
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('unpinned session does not show trailing push_pin when idle', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.push_pin), findsNothing);
  });

  testWidgets('context menu includes scheduled message action', (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();

    await _openContextMenu(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarSessionTile)),
    );
    expect(find.text(l10n.automationsSessionContextMenu), findsOneWidget);

    await _dismissContextMenu(tester);
  });

  testWidgets('context menu shows manage item when session has automations', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    automationCubit.emit(
      AutomationState(
        automations: [_sessionAutomation()],
        status: AutomationLoadStatus.ready,
      ),
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();

    await _openContextMenu(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarSessionTile)),
    );
    expect(find.text(l10n.automationsSessionContextMenu), findsOneWidget);
    expect(find.text(l10n.automationsManageSessionContextMenu), findsOneWidget);

    await _dismissContextMenu(tester);
  });

  testWidgets('waiting marker is visible and distinct from working spinner', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    chatCubit.emit(
      chatCubit.state.copyWith(workingSessionIds: {_session.sessionId}),
    );
    attention.applyEvent(
      sessionId: _session.sessionId,
      memberId: 'seat-a',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
      ),
    );
    await tester.pump();

    expect(find.byKey(AppKeys.sidebarSessionWaitingMarker), findsOneWidget);
    expect(find.byType(SessionWorkingSpinner), findsNothing);
  });

  testWidgets('working spinner shows when session is working without waiting', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    chatCubit.emit(
      chatCubit.state.copyWith(workingSessionIds: {_session.sessionId}),
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
      ),
    );
    await tester.pump();

    expect(find.byType(SessionWorkingSpinner), findsOneWidget);
    expect(find.byKey(AppKeys.sidebarSessionWaitingMarker), findsNothing);
  });

  testWidgets('launching pod (connecting) shows the sidebar working spinner', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    // Pod launching without any agent working yet — the sidebar must still
    // show the starting spinner (derived from pod phase, not workingSessionIds).
    chatCubit
        .ensurePodRuntime(_session.sessionId)
        .setPhase(SessionPhase.connecting);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
      ),
    );
    await tester.pump();

    expect(find.byType(SessionWorkingSpinner), findsOneWidget);
    expect(find.byKey(AppKeys.sidebarSessionWaitingMarker), findsNothing);
  });

  testWidgets('tap while waiting activates Terminal and first waiting seat', (
    tester,
  ) async {
    final chatCubit = _RecordingChatCubit();
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    attention.applyEvent(
      sessionId: _session.sessionId,
      memberId: 'seat-waiting',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );

    var activated = false;
    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
        onTap: () => activated = true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SidebarSessionTile));
    await tester.pump();

    expect(activated, isTrue);
    expect(chatCubit.selectedMembers, ['seat-waiting']);
    expect(chatCubit.workbenchViews, [
      (_session.sessionId, SessionWorkbenchView.terminal),
    ]);
  });

  testWidgets(
    'cross-session waiting jump awaits open before seat/Terminal',
    (tester) async {
      final sessionB = AppSession(
        sessionId: 'sess-b',
        workspaceId: 'ws1',
        createdAt: 1,
        updatedAt: 1,
      );
      final chatCubit = _RecordingChatCubit();
      final (attention, automationCubit) = _tileCubits();
      addTearDown(chatCubit.close);
      addTearDown(automationCubit.close);
      addTearDown(attention.close);

      // Session A is active; waiting is on B.
      chatCubit.emit(
        chatCubit.state.copyWith(
          activeSessionId: 'sess-a',
          selectedMemberId: 'member-a',
        ),
      );
      attention.applyEvent(
        sessionId: sessionB.sessionId,
        memberId: 'seat-b',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );

      final openCompleter = Completer<void>();
      await tester.pumpWidget(
        _host(
          chatCubit: chatCubit,
          automationCubit: automationCubit,
          sessionRepository: SessionRepository(),
          attentionCubit: attention,
          child: SidebarSessionTile(
            session: sessionB,
            onTap: () async {
              chatCubit.eventOrder.add('activate-start');
              await openCompleter.future;
              chatCubit.emit(
                chatCubit.state.copyWith(
                  activeSessionId: sessionB.sessionId,
                  selectedMemberId: '',
                ),
              );
              chatCubit.eventOrder.add('activate-done');
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SidebarSessionTile));
      await tester.pump();

      // Still opening B — must not selectMember / switch Terminal on A yet.
      expect(chatCubit.selectedMembers, isEmpty);
      expect(chatCubit.workbenchViews, isEmpty);
      expect(chatCubit.state.activeSessionId, 'sess-a');

      openCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(chatCubit.state.activeSessionId, sessionB.sessionId);
      expect(chatCubit.activeSessionAtSelectMember, [sessionB.sessionId]);
      expect(chatCubit.selectedMembers, ['seat-b']);
      expect(chatCubit.workbenchViews, [
        (sessionB.sessionId, SessionWorkbenchView.terminal),
      ]);
      expect(chatCubit.eventOrder, [
        'activate-start',
        'activate-done',
        'selectMember:seat-b',
        'workbench:sess-b',
      ]);
    },
  );
}
