@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import '../support/post_frame_test_harness.dart';
import 'support/integration_test_setup.dart';
import 'support/session_idle_busy_harness.dart';

/// Integration coverage for lazy spawn + idle reclaim. The reclaim threshold
/// is configured to 2 seconds so the tests run fast (see SessionPreferences
/// `reclaimIdleTerminalAfterSeconds`, runtime-configurable for exactly this).
void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  group('mixed team terminal lazy spawn + idle reclaim', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('it_reclaim_mixed_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        reclaimIdleTerminalsEnabled: () => true,
        reclaimIdleTerminalAfterSeconds: () => 2,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('idle worker terminal is reclaimed, then re-materializes on message',
        () async {
      await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final tab = cubit.activeTab!;
      final bus = tab.teamBus!;

      // Worker is running + idle at prompt (not lead, not displayed, no unread).
      expect(tab.memberShells.containsKey('worker-1'), isTrue);
      expect(bus.memberById('worker-1')!.lifecycle, MemberLifecycle.running);

      // Seed the idle timer, then wait past the 2s threshold.
      cubit.debugTickReclaimWatch();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      cubit.debugTickReclaimWatch();
      await drainPendingAsyncWork();

      expect(tab.memberShells.containsKey('worker-1'), isFalse,
        reason: 'idle worker terminal should be reclaimed');
      expect(bus.memberById('worker-1')!.lifecycle, MemberLifecycle.declared,
        reason: 'bus state resets so the materialize funnel can re-bring it up');
      expect(tab.reclaimedMemberIds, contains('worker-1'));

      // Leader sends a message → the materialize funnel re-engages: a fresh
      // shell is created and the bus member leaves `declared` (materializing →
      // running, `ptyRunning` true). The send resolves only once the
      // materialize completes, which happens in a postFrame callback — so
      // flush the postFrame scheduler while the send is pending.
      final sendFuture = bus.send(
        const TeamMessage(
          id: 're-engage',
          from: 'team-lead',
          to: 'worker-1',
          content: 'status?',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await postFrame.flush();
      await drainPendingAsyncWork();
      await sendFuture;
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(tab.memberShells.containsKey('worker-1'), isTrue,
        reason: 'message must re-create the reclaimed worker shell');
      expect(bus.memberById('worker-1')!.ptyRunning, isTrue,
        reason: 'message must take the reclaimed worker back online');
    });

    test('team lead terminal is never reclaimed', () async {
      await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final tab = cubit.activeTab!;

      cubit.debugTickReclaimWatch();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      cubit.debugTickReclaimWatch();
      await drainPendingAsyncWork();

      expect(tab.memberShells.containsKey('team-lead'), isTrue,
        reason: 'the lead terminal is protected from idle reclaim');
    });
  });

  group('simple mode idle reclaim + restore', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('it_reclaim_simple_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        reclaimIdleTerminalsEnabled: () => true,
        reclaimIdleTerminalAfterSeconds: () => 2,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('idle simple terminal is reclaimed; reconnect restores a shell',
        () async {
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/tmp'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);
      await cubit.loadWorkspaceData(repo);
      // connectImmediately:false — the harness must not attempt a real PTY
      // spawn (native lib is unavailable under `flutter test`).
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
      expect(tab.memberShells, isNotEmpty);

      cubit.debugTickReclaimWatch();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      cubit.debugTickReclaimWatch();
      await drainPendingAsyncWork();

      expect(tab.memberShells, isEmpty,
        reason: 'idle simple terminal should be reclaimed');
      expect(tab.reclaimedMemberIds, isNotEmpty);

      // Restore via the same reconnect path the UI placeholder triggers. The
      // materialize funnel re-creates the shell even though the real PTY spawn
      // is unavailable here (covered by real-CLI integration elsewhere).
      await cubit.retrySessionLaunch(session.sessionId);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(tab.memberShells, isNotEmpty,
        reason: 'reconnect must re-create the reclaimed simple terminal shell');
    });
  });
}
