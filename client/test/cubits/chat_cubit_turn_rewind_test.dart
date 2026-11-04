import 'dart:async';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/chat/conversation/history/ai_history_loader.dart';
import 'package:teampilot/services/chat/conversation/history/session_history_context_builder.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

import '../integration/support/session_idle_busy_harness.dart';
import '../support/post_frame_test_harness.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  test(
    'attention-done on a local Claude simple session commits the cached turn',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cubit_turn_rewind_');
      final storage = fakeHomeStorage();
      final repo = SessionRepository(rootDir: tmp.path, storage: storage);
      final attention = AgentAttentionCubit(pruneInterval: null);
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        agentAttentionCubit: attention,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
        storage: storage,
      );
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => storage.context,
      );
      cubit.historyLoader = loader;

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        cli: CliTool.claude,
      )).session;
      await cubit.loadWorkspaceData(repo);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repo,
          connectImmediately: false,
        ),
      );
      await drainPendingAsyncWork();
      final tab = cubit.activeTab!;
      final memberId = tab.memberShells.keys.single;
      tab.persistedSession = tab.persistedSession!.withNativeSessionId(
        CliTool.claude.value,
        'native-1',
      );
      const lastId = 'msg-last';

      final commits = <RewindCheckpoint>[];
      final storeArgs =
          <({String gitDir, String workTree, SeatRewindTarget target})>[];
      cubit.debugCommitPtyTurn =
          ({
            required gitDir,
            required workTree,
            required target,
            required messageId,
            nativeSessionId,
          }) async {
            storeArgs.add((gitDir: gitDir, workTree: workTree, target: target));
            final checkpoint = RewindCheckpoint(
              commit: 'c1',
              messageId: messageId,
              nativeSessionId: nativeSessionId,
            );
            commits.add(checkpoint);
            return checkpoint;
          };

      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'afterAgentResponse',
        ),
        skipPermissions: false,
      );
      await drainPendingAsyncWork();
      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: [
          AiMessage(
            id: lastId,
            role: AiRole.assistant,
            parts: const [AiTextPart(text: 'done')],
          ),
        ],
        cli: CliTool.claude,
      );
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.done,
          hookEventName: 'Stop',
        ),
        skipPermissions: false,
      );
      await drainPendingAsyncWork();

      expect(commits, hasLength(1));
      expect(commits.single.messageId, lastId);
      expect(commits.single.nativeSessionId, 'native-1');
      expect(storeArgs.single.target.kind, SeatRewindKind.personalPty);
      expect(storeArgs.single.target.seatKey, 'personal');
      final layout = storage.context.layout;
      expect(
        storeArgs.single.gitDir,
        layout.pathContext.join(
          layout.workspace.sessionDir(workspace.workspaceId, session.sessionId),
          'rewind',
          'personal',
        ),
      );
      expect(
        storeArgs.single.workTree,
        layout.workspace.sessionRuntimeDir(
          workspace.workspaceId,
          session.sessionId,
        ),
      );

      await cubit.close();
      await attention.close();
      await postFrame.flush();
      await deleteTempDirBestEffort(tmp);
    },
  );

  test(
    'a stale cached id is not kept until history observes the closing message',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cubit_turn_rewind_');
      final storage = fakeHomeStorage();
      final repo = SessionRepository(rootDir: tmp.path, storage: storage);
      final attention = AgentAttentionCubit(pruneInterval: null);
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        agentAttentionCubit: attention,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
        storage: storage,
      );
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => storage.context,
      );
      cubit.historyLoader = loader;

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        cli: CliTool.claude,
      )).session;
      await cubit.loadWorkspaceData(repo);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repo,
          connectImmediately: false,
        ),
      );
      await drainPendingAsyncWork();
      final memberId = cubit.activeTab!.memberShells.keys.single;
      final commits = <String>[];
      cubit.debugCommitPtyTurn =
          ({
            required gitDir,
            required workTree,
            required target,
            required messageId,
            nativeSessionId,
          }) async {
            commits.add(messageId);
            return RewindCheckpoint(
              commit: 'c-$messageId',
              messageId: messageId,
              nativeSessionId: nativeSessionId,
            );
          };

      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'm-old',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'old')],
          ),
        ],
        cli: CliTool.claude,
      );
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'afterAgentResponse',
        ),
        skipPermissions: false,
      );
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.done,
          hookEventName: 'Stop',
        ),
        skipPermissions: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(commits, isEmpty);

      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'm-old',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'old')],
          ),
          AiMessage(
            id: 'm-new',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'new')],
          ),
        ],
        cli: CliTool.claude,
      );
      await drainPendingAsyncWork();

      expect(commits, ['m-new']);

      await cubit.close();
      await attention.close();
      await postFrame.flush();
      await deleteTempDirBestEffort(tmp);
    },
  );

  test(
    'a quiet end keeps only an id that appears after the shell latch starts',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cubit_turn_rewind_');
      final storage = fakeHomeStorage();
      final repo = SessionRepository(rootDir: tmp.path, storage: storage);
      final attention = AgentAttentionCubit(pruneInterval: null);
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        agentAttentionCubit: attention,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
        storage: storage,
      );
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => storage.context,
      );
      cubit.historyLoader = loader;

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        cli: CliTool.cursor,
      )).session;
      await cubit.loadWorkspaceData(repo);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repo,
          connectImmediately: false,
        ),
      );
      await drainPendingAsyncWork();
      final tab = cubit.activeTab!;
      final memberId = tab.memberShells.keys.single;
      final shell = tab.memberShells.values.single;
      final commits = <String>[];
      cubit.debugCommitPtyTurn =
          ({
            required gitDir,
            required workTree,
            required target,
            required messageId,
            nativeSessionId,
          }) async {
            commits.add(messageId);
            return RewindCheckpoint(
              commit: 'c-$messageId',
              messageId: messageId,
              nativeSessionId: nativeSessionId,
            );
          };

      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'm-before',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'before')],
          ),
        ],
        cli: CliTool.cursor,
      );

      final skipped = Stopwatch()..start();
      await cubit.debugCheckpointPtyTurn(session.sessionId, memberId);
      await drainPendingAsyncWork();
      skipped.stop();
      expect(commits, isEmpty);
      expect(skipped.elapsed, lessThan(const Duration(milliseconds: 500)));

      shell.markUserTurnStarted();
      cubit.debugTickIdleWatch();
      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'm-before',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'before')],
          ),
          AiMessage(
            id: 'm-after',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'after')],
          ),
        ],
        cli: CliTool.cursor,
      );
      simulateFingerprintQuietGap(shell);
      cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();

      expect(commits, ['m-after']);

      await cubit.close();
      await attention.close();
      await postFrame.flush();
      await deleteTempDirBestEffort(tmp);
    },
  );

  test(
    'a quiet end publishes idle only after the checkpoint completes',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cubit_turn_rewind_');
      final storage = fakeHomeStorage();
      final repo = SessionRepository(rootDir: tmp.path, storage: storage);
      final attention = AgentAttentionCubit(pruneInterval: null);
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        agentAttentionCubit: attention,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
        storage: storage,
      );
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => storage.context,
      );
      cubit.historyLoader = loader;

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        cli: CliTool.cursor,
      )).session;
      await cubit.loadWorkspaceData(repo);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repo,
          connectImmediately: false,
        ),
      );
      await drainPendingAsyncWork();
      final tab = cubit.activeTab!;
      final memberId = tab.memberShells.keys.single;
      final shell = tab.memberShells.values.single;

      final started = Completer<void>();
      final release = Completer<void>();
      cubit.debugCommitPtyTurn =
          ({
            required gitDir,
            required workTree,
            required target,
            required messageId,
            nativeSessionId,
          }) async {
            started.complete();
            await release.future;
            return RewindCheckpoint(
              commit: 'c-$messageId',
              messageId: messageId,
              nativeSessionId: nativeSessionId,
            );
          };

      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'm-before',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'before')],
          ),
        ],
        cli: CliTool.cursor,
      );
      shell.markUserTurnStarted();
      cubit.debugTickIdleWatch();
      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'm-before',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'before')],
          ),
          AiMessage(
            id: 'm-after',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'after')],
          ),
        ],
        cli: CliTool.cursor,
      );
      simulateFingerprintQuietGap(shell);
      cubit.debugTickIdleWatch();
      await started.future;

      // The seat is still in its turn, so a queued follow-up cannot drain
      // while the checkpoint walks the runtime directory.
      expect(shell.userTurnActive, isTrue);
      expect(cubit.isMemberWorking(session.sessionId, memberId), isTrue);

      release.complete();
      await waitUntil(() => !shell.userTurnActive);

      expect(shell.userTurnActive, isFalse);
      expect(cubit.isMemberWorking(session.sessionId, memberId), isFalse);

      await cubit.close();
      await attention.close();
      await postFrame.flush();
      await deleteTempDirBestEffort(tmp);
    },
  );
}
