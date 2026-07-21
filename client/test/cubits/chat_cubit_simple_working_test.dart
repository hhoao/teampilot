import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';

/// Running fake so the non-bus idle-watch branch does not skip it.
class _RunningFakeSession extends TerminalSession {
  _RunningFakeSession({required super.executable});

  @override
  bool get isRunning => true;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit simple-mode working indicator', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late AgentAttentionCubit attention;
    late PostFrameTestHarness postFrame;
    final created = <_RunningFakeSession>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chat_simple_working_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      created.clear();
      attention = AgentAttentionCubit(pruneInterval: null);
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        agentAttentionCubit: attention,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final s = _RunningFakeSession(executable: executable);
              created.add(s);
              return s;
            },
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await attention.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('send lights working; screen going quiet clears it', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);
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
      expect(cubit.state.tabs.length, 1);
      final shell = created.single;

      // Idle before any send: not working.
      cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();
      expect(cubit.state.workingSessionIds, isEmpty);

      // Send → turn starts; agent output makes the activity tracker active.
      shell.markUserTurnStarted();
      shell.activityTracker.isWorking; // arm past the boot-quiet window
      shell.activityTracker.markActive();
      cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();
      expect(
        cubit.state.workingSessionIds,
        contains(session.sessionId),
        reason: 'a send should light the working indicator',
      );

      // Screen goes quiet (PTY fingerprint unchanged for idleAfter) → falling
      // edge clears the turn.
      shell.activityTracker.notePtyBytes(
        const [0x64, 0x6f, 0x6e, 0x65], // "done"
        DateTime.now().subtract(const Duration(seconds: 5)),
      );
      cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();
      expect(cubit.state.workingSessionIds, isEmpty);
    });

    test(
      'operator latch must not pin busy after PTY quiet (Cursor simple)',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
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
        final shell = created.single;
        final memberId = cubit.activeTab!.memberShells.keys.single;

        // Real submit path: shell latch + operator-turn callback (attention).
        shell.markUserTurnStarted();
        cubit.debugNotifyOperatorTurnLatched(session.sessionId, memberId);
        shell.activityTracker.isWorking;
        shell.activityTracker.markActive();
        cubit.debugTickIdleWatch();
        await drainPendingAsyncWork();
        expect(cubit.state.workingSessionIds, contains(session.sessionId));

        shell.activityTracker.notePtyBytes(
          const [0x64, 0x6f, 0x6e, 0x65],
          DateTime.now().subtract(const Duration(seconds: 5)),
        );
        cubit.debugTickIdleWatch();
        await drainPendingAsyncWork();
        expect(
          cubit.state.workingSessionIds,
          isEmpty,
          reason:
              'CLIs without Stop/done must not stay busy via latch-stamped '
              'attention.working after PTY quiet ends the turn',
        );
        expect(
          attention.state.attentionFor(
            sessionId: session.sessionId,
            memberId: memberId,
          ),
          isNull,
        );
      },
    );

    test(
      'operator latch clears sticky waiting so a new turn can show spinner',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
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

        attention.applyEvent(
          sessionId: session.sessionId,
          memberId: memberId,
          event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
          skipPermissions: false,
        );
        expect(
          attention.state.attentionFor(
            sessionId: session.sessionId,
            memberId: memberId,
          ),
          AgentSeatAttention.waiting,
        );

        cubit.debugNotifyOperatorTurnLatched(session.sessionId, memberId);
        expect(
          attention.state.attentionFor(
            sessionId: session.sessionId,
            memberId: memberId,
          ),
          isNull,
          reason: 'fresh submit clears sticky waiting without stamping working',
        );
      },
    );

    test(
      'personal send recomputes working even with stale team presence',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
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

        final presenceCubit = MemberPresenceCubit();
        cubit.bindPresenceCubit(presenceCubit);
        presenceCubit.emit(
          const MemberPresenceState(
            presence: {
              'team-lead': MemberPresence(
                connection: MemberConnection.connected,
                availability: MemberAvailability.idle,
              ),
            },
          ),
        );

        final shell = cubit.activeTab!.memberShells.values.single;
        shell.activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(seconds: 5)),
        );
        shell.markUserTurnStarted();

        cubit.debugRecomputeWorkingSessions();

        expect(
          cubit.state.workingSessionIds,
          contains(session.sessionId),
          reason: 'personal tab must not mirror unrelated team presence',
        );
        await presenceCubit.close();
      },
    );

    test('real 1s idle-watch timer is running for a simple-mode tab', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);
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
      final shell = created.single;

      shell.markUserTurnStarted();
      shell.activityTracker.isWorking; // arm
      shell.activityTracker.markActive();

      // No manual tick — rely on the periodic timer started at tab open.
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(
        cubit.state.workingSessionIds,
        contains(session.sessionId),
        reason: 'ensureIdleWatch must start the periodic timer at tab open',
      );
    });

    test(
      'agent-status working keeps sidebar busy after PTY turn latch ends',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
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
        final shell = created.single;
        final memberId = cubit.activeTab!.memberShells.keys.single;

        // Simulate permission hold ending the PTY latch (quiet wait).
        shell.markUserTurnStarted();
        cubit.debugTickIdleWatch();
        await drainPendingAsyncWork();
        expect(cubit.state.workingSessionIds, contains(session.sessionId));

        shell.markUserTurnIdle();
        cubit.debugRecomputeWorkingSessions();
        expect(cubit.state.workingSessionIds, isEmpty);

        // Permission cleared → hook working (Orca). Latch stays false.
        attention.applyEvent(
          sessionId: session.sessionId,
          memberId: memberId,
          event: const AgentStatusEvent(
            state: AgentSeatAttention.working,
            hookEventName: 'PostToolUse',
            toolName: 'Bash',
            toolUseId: 'toolu-1',
          ),
          skipPermissions: false,
        );
        await drainPendingAsyncWork();
        expect(
          cubit.state.workingSessionIds,
          contains(session.sessionId),
          reason: 'attention.working must light sidebar after permission',
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
        expect(cubit.state.workingSessionIds, isEmpty);
      },
    );
  });
}
