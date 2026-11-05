import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

import '../support/fake_terminal_session.dart';
import '../support/fixed_resume_lifecycle_service.dart';
import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('editing restores the parent and sends the new text', () async {
    final env = await _openPersonal();
    final store = env.store;
    final first = await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.commitTurn(messageId: 'a2', userMessageId: 'u2');
    final sent = <String>[];
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async {
          sent.add(message);
          // The real send is followed by the new turn's end checkpoint; record
          // that turn here so the edited turn lands as a sibling.
          await store.commitTurn(messageId: 'a3', userMessageId: 'u2');
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        };

    await env.cubit.editSeatTurn(
      sessionId: env.session.sessionId,
      memberId: env.session.sessionId,
      userMessageId: 'u2',
      text: 'edited text',
    );

    expect(sent, ['edited text']);
    final turns = await store.checkpoints();
    expect(turns.where((t) => t.userMessageId == 'u2'), hasLength(2));
    expect(
      turns.where((t) => t.userMessageId == 'u2').map((t) => t.parentCommit),
      everyElement(first.commit),
    );
  });

  test(
    'a failed send surfaces the error and puts the previous branch back',
    () async {
      final env = await _openPersonal();
      final store = env.store;
      await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
      final second = await store.commitTurn(
        messageId: 'a2',
        userMessageId: 'u2',
      );
      env.cubit.debugDeliverEditedMessage =
          ({required sessionId, required memberId, required message}) async {
            // A failed send still latches a turn; the rollback must not be
            // refused by the turn-in-flight guard.
            env.cubit.debugMarkTurnInFlight(sessionId);
            throw StateError('delivery exploded');
          };

      await expectLater(
        env.cubit.editSeatTurn(
          sessionId: env.session.sessionId,
          memberId: env.session.sessionId,
          userMessageId: 'u2',
          text: 'edited text',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'delivery exploded',
          ),
        ),
      );

      expect(await store.checkedOut(), second.commit);
      expect(
        env.cubit.state.rewindForkInProgress.contains(env.session.sessionId),
        isFalse,
      );
    },
  );

  test('a refused parent restore does not rewind the running seat', () async {
    final env = await _openPersonal();
    final store = env.store;
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    final second = await store.commitTurn(messageId: 'a2', userMessageId: 'u2');
    // A tap landing on the frame a turn starts: the parent restore must be
    // refused, and the rollback must not force-rewind the running turn.
    env.cubit.debugMarkTurnInFlight(env.session.sessionId);
    final sent = <String>[];
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async {
          sent.add(message);
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        };

    await expectLater(
      env.cubit.editSeatTurn(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        userMessageId: 'u2',
        text: 'edited text',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Cannot rewind while a turn is in flight',
        ),
      ),
    );

    expect(sent, isEmpty);
    // No second rewind: the seat is never stopped or relaunched.
    expect(env.cubit.relaunchCalls, isEmpty);
    expect(await store.checkedOut(), second.commit);
    expect(
      env.cubit.state.rewindForkInProgress.contains(env.session.sessionId),
      isFalse,
    );
  });

  test('a rejected send reports the delivery failure', () async {
    final env = await _openPersonal();
    await env.store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async =>
            const HistoryContinueSubmitResult.failed();

    await expectLater(
      env.cubit.editSeatTurn(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        userMessageId: 'u1',
        text: 'edited text',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'The edited message was not delivered',
        ),
      ),
    );
  });

  test('editing the first message restores the root', () async {
    final env = await _openPersonal();
    final store = env.store;
    final root = await store.root();
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    String? rootAtSend;
    RewindCheckpoint? edited;
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async {
          rootAtSend = await store.checkedOut();
          // The real send is followed by the new turn's end checkpoint.
          edited = await store.commitTurn(messageId: 'a2', userMessageId: 'u1');
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        };

    await env.cubit.editSeatTurn(
      sessionId: env.session.sessionId,
      memberId: env.session.sessionId,
      userMessageId: 'u1',
      text: 'edited first message',
    );

    expect(rootAtSend, root);
    expect(edited!.parentCommit, root);
  });

  test('the cubit owns the optimistic edit until it is cleared', () async {
    final env = await _openPersonal();
    final store = env.store;
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.commitTurn(messageId: 'a2', userMessageId: 'u2');
    final gate = Completer<void>();
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async {
          await gate.future;
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        };

    final edit = env.cubit.editSeatTurn(
      sessionId: env.session.sessionId,
      memberId: env.session.sessionId,
      userMessageId: 'u2',
      text: 'edited text',
    );

    final pending = env.cubit.branchEditFor(env.session.sessionId).pending;
    expect(pending?.messageId, 'u2');
    expect(pending?.text, 'edited text');

    gate.complete();
    await edit;

    expect(
      env.cubit.branchEditFor(env.session.sessionId).pending,
      isNotNull,
      reason: 'the runtime has not published the new prompt yet',
    );

    env.cubit.clearPendingBranchEdit(env.session.sessionId);
    expect(env.cubit.branchEditFor(env.session.sessionId).pending, isNull);
  });
}

Future<_Env> _openPersonal() async {
  final repo = SessionRepository(storage: testHomeStorage);
  final postFrame = PostFrameTestHarness();
  final cubit = _HarnessCubit(repo: repo, postFrame: postFrame);
  addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));

  final workspace = await repo.createWorkspace([
    const WorkspaceFolder(path: '/work'),
  ]);
  final session = (await repo.createSession(
    workspace.workspaceId,
    cli: CliTool.claude,
  )).session;
  await cubit.loadWorkspaceData(repo);
  cubit.activateWorkspaceTab(
    workspaceTabKey: workspace.workspaceId,
    scopeSessionsToSelectedTeam: false,
  );
  await cubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      workspace: workspace,
      repo: repo,
      connectImmediately: false,
    ),
  );
  await drainPendingAsyncWork();
  final tab = cubit.tabStore.getOpenTabBySessionId(session.sessionId)!;
  final layout = testHomeStorage.context.layout;
  final workTree = layout.workspace.sessionRuntimeDir(
    workspace.workspaceId,
    session.sessionId,
  );
  await Directory(workTree).create(recursive: true);
  final store = SeatRewindStore(
    gitDir: layout.pathContext.join(
      layout.workspace.sessionDir(workspace.workspaceId, session.sessionId),
      'rewind',
      'personal',
    ),
    workTree: workTree,
    target: const SeatRewindTarget(
      kind: SeatRewindKind.personalPty,
      tool: 'claude',
    ),
  );
  return _Env(
    cubit: cubit,
    repo: repo,
    session: tab.persistedSession ?? session,
    store: store,
  );
}

final class _Env {
  const _Env({
    required this.cubit,
    required this.repo,
    required this.session,
    required this.store,
  });

  final _HarnessCubit cubit;
  final SessionRepository repo;
  final AppSession session;
  final SeatRewindStore store;
}

final class _HarnessCubit extends ChatCubit {
  _HarnessCubit({
    required SessionRepository repo,
    required PostFrameTestHarness postFrame,
  }) : super(
         executableResolver: () => 'flashskyai',
         automationRepository: testAutomationRepository(),
         sessionRepository: repo,
         terminalSessionFactory:
             ({required String executable, int scrollbackLines = 10000}) =>
                 FakeTerminalSession(
                   executable: executable,
                   scrollbackLines: scrollbackLines,
                   fs: InMemoryFilesystem(),
                 ),
         postFrameScheduler: postFrame.scheduler,
         lifecycleService: FixedResumeLifecycleService(resume: false),
         storage: testHomeStorage,
       );

  final relaunchCalls = <String>[];

  /// Latches a busy reason the way a real send does, so the seat process
  /// reports a turn in flight.
  void debugMarkTurnInFlight(String sessionId) {
    emit(
      state.copyWith(
        sessionActivities: {
          ...state.sessionActivities,
          sessionId: const SessionActivity(reasons: {SessionBusyReason.inTurn}),
        },
      ),
    );
  }

  @override
  Future<void> retrySessionLaunch(
    String sessionId, {
    String? firstPrompt,
  }) async {
    relaunchCalls.add('retry:$sessionId');
  }

  @override
  Future<void> ensureMemberTerminalForView(
    String sessionId,
    String memberId,
  ) async {
    relaunchCalls.add('ensure:$sessionId:$memberId');
  }
}
