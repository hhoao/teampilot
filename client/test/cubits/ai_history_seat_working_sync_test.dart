import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/history_awaiting_working_sync.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

/// Seat-owned working latch — survives remount; drives Starting/Running sync.
void main() {
  late AiHistoryCubit cubit;

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );

  WorkspaceLaunchContext launchCtx(AppSession s) => WorkspaceLaunchContext(
    session: s,
    workspace: Workspace(
      workspaceId: s.workspaceId,
      folders: s.folders,
      createdAt: 0,
    ),
  );

  setUp(() {
    setUpTestAppStorage();
    final fs = LocalFilesystem();
    final adapter = _EmptyAdapter();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: adapter,
    );
    final loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/ai-history-seat-sync',
        cwd: '/tmp/ai-history-seat-sync',
        appDataRoot: '/tmp/ai-history-seat-sync',
        paths: AppPaths('/tmp/ai-history-seat-sync'),
      ),
      locator: _EmptyLocator(registry: registry),
      registry: registry,
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('enqueue resets latch and marks awaiting', () async {
    final session = simpleSession();
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    final seat = cubit.ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: '',
    );

    seat.enqueuePendingUser('hi');
    expect(seat.state.awaitingAssistant, isTrue);
    expect(seat.sawWorkingWhileAwaiting, isFalse);
    expect(seat.hasOptimisticPending, isTrue);

    expect(
      seat.applyWorkingSessionSync(sessionWorking: true),
      HistoryAwaitingWorkingAction.latchWorking,
    );
    expect(seat.sawWorkingWhileAwaiting, isTrue);

    // Next turn must not inherit the previous rising edge.
    seat.enqueuePendingUser('again');
    expect(seat.sawWorkingWhileAwaiting, isFalse);
    expect(seat.state.awaitingAssistant, isTrue);
  });

  test('falling edge clears awaiting via seat sync', () async {
    final session = simpleSession();
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    final seat = cubit.ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: '',
    );

    seat.enqueuePendingUser('hi');
    seat.applyWorkingSessionSync(sessionWorking: true);
    expect(seat.sawWorkingWhileAwaiting, isTrue);

    expect(
      seat.applyWorkingSessionSync(sessionWorking: false),
      HistoryAwaitingWorkingAction.clearAwaiting,
    );
    expect(seat.state.awaitingAssistant, isFalse);
    expect(seat.sawWorkingWhileAwaiting, isFalse);
  });

  test(
    'first-send connect defers — keeps awaiting without latching or clearing',
    () async {
      final session = simpleSession();
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      final seat = cubit.ensureSeat(
        sessionId: session.sessionId,
        selectedMemberId: '',
      );

      // Landing seed / optimistic continue before PTY is up.
      seat.enqueuePendingUser('能不能做个番茄钟');
      expect(
        seat.applyWorkingSessionSync(
          sessionWorking: false,
          sessionConnecting: true,
          memberRunning: false,
        ),
        HistoryAwaitingWorkingAction.deferWhileStarting,
      );
      expect(seat.state.awaitingAssistant, isTrue);
      expect(seat.sawWorkingWhileAwaiting, isFalse);

      // SoftReload / remount sync with same signals must still defer.
      expect(
        seat.applyWorkingSessionSync(
          sessionWorking: false,
          sessionConnecting: true,
          memberRunning: false,
        ),
        HistoryAwaitingWorkingAction.deferWhileStarting,
      );
      expect(seat.state.awaitingAssistant, isTrue);
    },
  );

  test('latch survives softReload so remount can clear on idle edge', () async {
    final session = simpleSession();
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    final seat = cubit.ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: '',
    );

    seat.enqueuePendingUser('hi');
    seat.applyWorkingSessionSync(sessionWorking: true);
    expect(seat.sawWorkingWhileAwaiting, isTrue);

    await seat.softReload();

    // Widget remount lost its local latch historically; seat keeps it.
    expect(seat.sawWorkingWhileAwaiting, isTrue);
    expect(seat.state.awaitingAssistant, isTrue);

    expect(
      seat.applyWorkingSessionSync(
        sessionWorking: false,
        memberRunning: true,
      ),
      HistoryAwaitingWorkingAction.clearAwaiting,
    );
    expect(seat.state.awaitingAssistant, isFalse);
  });

  test('flushHeldTip(endAwaiting) clears latch', () async {
    final session = simpleSession();
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    final seat = cubit.ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: '',
    );

    seat.enqueuePendingUser('hi');
    seat.applyWorkingSessionSync(sessionWorking: true);
    seat.flushHeldTip(endAwaiting: true);

    expect(seat.state.awaitingAssistant, isFalse);
    expect(seat.sawWorkingWhileAwaiting, isFalse);
  });

  test(
    'member up + idle without latch → scheduleGraceClear (not force clear)',
    () async {
      final session = simpleSession();
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      final seat = cubit.ensureSeat(
        sessionId: session.sessionId,
        selectedMemberId: '',
      );

      seat.enqueuePendingUser('hi');
      expect(
        seat.applyWorkingSessionSync(
          sessionWorking: false,
          sessionConnecting: false,
          memberRunning: true,
        ),
        HistoryAwaitingWorkingAction.scheduleGraceClear,
      );
      expect(seat.state.awaitingAssistant, isTrue);
    },
  );
}

class _EmptyAdapter implements AiTranscriptAdapter {
  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}

class _EmptyLocator extends AiHistoryLocator {
  _EmptyLocator({required super.registry});

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async => null;
}
