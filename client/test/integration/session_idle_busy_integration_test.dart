@Tags(['integration', 'cross-platform'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';
import 'support/integration_test_setup.dart';
import 'support/session_idle_busy_harness.dart';

class _SimpleRunningShell extends TerminalSession {
  _SimpleRunningShell({required super.executable});

  @override
  bool get isRunning => true;

  @override
  void dispose() {}
}

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  group('mixed team session idle/busy (ChatCubit + TeamBus)', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('it_idle_busy_mixed_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
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

    test('session idle when all members at prompt', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = cubit.activeTab!.teamBus!;

      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, isEmpty);

      bus.markTurnStarted('worker-1');
      cubit.debugTickIdleWatch();
      expect(
        cubit.state.workingSessionIds,
        contains(opened.sessionId),
        reason: 'in-turn member should light the session spinner',
      );

      bus.onMemberIdle('worker-1');
      cubit.debugTickIdleWatch();
      expect(
        cubit.state.workingSessionIds,
        isEmpty,
        reason: 'turn end should clear session working',
      );
    });

    test('PTY spinner output does not light mixed session working', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final tab = cubit.activeTab!;

      // All members idle-at-prompt on the bus; PTY would look "busy".
      for (final shell in tab.memberShells.values) {
        shell.activityTracker.markActive();
      }

      cubit.debugTickIdleWatch();
      expect(
        cubit.state.workingSessionIds,
        isEmpty,
        reason:
            'mixed mode must not infer working from PTY bytes (spinner repaint)',
      );

      // Sanity: bus turn still lights working.
      tab.teamBus!.markTurnStarted('team-lead');
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, contains(opened.sessionId));
    });

    test('HTTP POST /idle blocks CLI without ending bus turn', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = cubit.activeTab!.teamBus!;
      final mcp = cubit.teammateBusMcpEndpointForSession(opened.sessionId)!;
      final idle = idleEndpointFromMcp(mcp);

      bus.markTurnStarted('team-lead');
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, contains(opened.sessionId));

      await postMemberIdle(idle, 'team-lead');
      cubit.debugTickIdleWatch();
      expect(bus.isMemberInTurn('team-lead'), isTrue);
      expect(
        cubit.state.workingSessionIds,
        contains(opened.sessionId),
        reason: 'Stop-hook /idle must not call onMemberIdle',
      );
    });

    test(
      'PTY quiet after turn activity ends bus turn and may doorbell mid-turn mail',
      () async {
        final opened = await openMixedSessionWithShells(
          cubit: cubit,
          repo: repo,
          postFrame: postFrame,
        );
        final tab = cubit.activeTab!;
        final bus = tab.teamBus!;
        final worker = opened.workerShell;

        bus.markTurnStarted('worker-1');
        await worker.emitPtyOutput('tool output\r\n');
        cubit.debugTickIdleWatch();
        expect(bus.isMemberInTurn('worker-1'), isTrue);
        expect(worker.ptyInputJoined, isEmpty);

        await bus.send(
          const TeamMessage(
            id: 'mid-turn-ping',
            from: 'team-lead',
            to: 'worker-1',
            content: 'status?',
          ),
        );
        expect(bus.isMemberInTurn('worker-1'), isTrue);
        expect(await bus.unreadCountFor('worker-1'), 1);
        expect(worker.ptyInputJoined, isEmpty);

        worker.simulateQuietGap();
        cubit.debugTickIdleWatch();
        await drainPendingAsyncWork();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(bus.isMemberInTurn('worker-1'), isFalse);
        expect(
          worker.ptyInput.where((w) => w.contains('teammate-bus')),
          isNotEmpty,
          reason:
              'PTY quiet after activity ends turn; pending mail doorbells at prompt',
        );
        expect(cubit.state.workingSessionIds, isEmpty);
      },
    );

    test('PTY quiet after turn activity ends mixed bus turn', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = cubit.activeTab!.teamBus!;
      final shell = cubit.activeTab!.memberShells['team-lead']!;

      bus.markTurnStarted('team-lead');
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, contains(opened.sessionId));

      simulateFingerprintQuietGap(shell);
      cubit.debugTickIdleWatch();
      expect(
        bus.isMemberInTurn('team-lead'),
        isFalse,
        reason: 'mixed bus turn ends when PTY fingerprint is quiet after activity',
      );
      expect(
        cubit.state.workingSessionIds,
        isEmpty,
      );
    });

    test('bus turn survives until idleAfter without PTY bytes', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = cubit.activeTab!.teamBus!;

      bus.markTurnStarted('team-lead');
      cubit.debugTickIdleWatch();
      expect(bus.isMemberInTurn('team-lead'), isTrue);
      expect(cubit.state.workingSessionIds, contains(opened.sessionId));
    });

    test('bus turn ends when member enters wait_for_message, not on Stop-hook',
        () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = cubit.activeTab!.teamBus!;
      final mcp = cubit.teammateBusMcpEndpointForSession(opened.sessionId)!;
      final idle = idleEndpointFromMcp(mcp);

      bus.markTurnStarted('team-lead');
      cubit.debugTickIdleWatch();
      expect(bus.isMemberInTurn('team-lead'), isTrue);

      await postMemberIdle(idle, 'team-lead');
      cubit.debugTickIdleWatch();
      expect(bus.isMemberInTurn('team-lead'), isTrue);

      unawaited(bus.receive('team-lead'));
      await Future<void>.delayed(Duration.zero);
      expect(bus.isWaitingForMessage('team-lead'), isTrue);
      expect(bus.isMemberInTurn('team-lead'), isFalse);
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, isEmpty);
    });

    test('member parked in wait_for_message is idle on bus and session', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = cubit.activeTab!.teamBus!;
      final shell = cubit.activeTab!.memberShells['team-lead']!;

      bus.markTurnStarted('team-lead');
      final waiting = bus.receive('team-lead');
      await Future<void>.delayed(Duration.zero);

      shell.activityTracker.markActive();
      cubit.debugTickIdleWatch();
      expect(
        cubit.state.workingSessionIds,
        isEmpty,
        reason: 'wait_for_message parks the member as idle',
      );
      expect(bus.isWaitingForMessage('team-lead'), isTrue);
      expect(bus.isMemberInTurn('team-lead'), isFalse);

      bus.memberById('team-lead')!.inbox.deliver(
        const TeamMessage(
          id: '1',
          from: 'worker-1',
          to: 'team-lead',
          content: 'ping',
        ),
      );
      final batch = await waiting;
      expect(batch, hasLength(1));
    });
  });

  group('mixed team member presence (MemberPresenceCubit + TeamBus)', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit chatCubit;
    late MemberPresenceCubit presenceCubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('it_idle_busy_presence_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      presenceCubit = MemberPresenceCubit();
      chatCubit = ChatCubit(
        executableResolver: () => 'true',
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
      );
      bindPresenceForPolling(
        chatCubit: chatCubit,
        presenceCubit: presenceCubit,
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await chatCubit.close();
      await presenceCubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('presence idle when bus turn ends even if PTY still active', () async {
      await openMixedSessionWithShells(
        cubit: chatCubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = chatCubit.activeTab!.teamBus!;
      final shell = chatCubit.activeTab!.memberShells['team-lead']!;
      bus.markTurnStarted('team-lead');
      bus.onMemberIdle('team-lead');
      armActivityTracker(shell);
      await postFrame.flush();
      await pumpSchedulerFrames();

      await waitForPresencePoll(cubit: chatCubit);
      await pumpSchedulerFrames();
      await waitUntil(
        () => presenceCubit.state.presence.containsKey('team-lead'),
      );

      expect(bus.isMemberInTurn('team-lead'), isFalse);
      expect(
        presenceCubit.memberPresenceFor('team-lead').workload,
        MemberWorkload.idle,
        reason: 'mixed presence follows TeamBus only',
      );
    });

    test('presence idle at prompt when bus and PTY are both quiet', () async {
      await openMixedSessionWithShells(
        cubit: chatCubit,
        repo: repo,
        postFrame: postFrame,
      );
      await postFrame.flush();
      await pumpSchedulerFrames();

      await waitForPresencePoll(cubit: chatCubit);
      await pumpSchedulerFrames();
      await waitUntil(
        () => presenceCubit.state.presence.containsKey('team-lead'),
      );

      expect(
        presenceCubit.memberPresenceFor('team-lead').workload,
        MemberWorkload.idle,
      );
    });

    test('presence working when member in bus turn', () async {
      await openMixedSessionWithShells(
        cubit: chatCubit,
        repo: repo,
        postFrame: postFrame,
      );
      chatCubit.activeTab!.teamBus!.markTurnStarted('worker-1');
      await postFrame.flush();
      await pumpSchedulerFrames();

      await waitForPresencePoll(cubit: chatCubit);
      await pumpSchedulerFrames();
      await waitUntil(
        () => presenceCubit.state.presence.containsKey('worker-1'),
      );

      expect(
        presenceCubit.memberPresenceFor('worker-1').workload,
        MemberWorkload.working,
      );
      expect(
        presenceCubit.memberPresenceFor('team-lead').workload,
        MemberWorkload.idle,
      );
    });

    test('presence idle when member blocks in wait_for_message', () async {
      await openMixedSessionWithShells(
        cubit: chatCubit,
        repo: repo,
        postFrame: postFrame,
      );
      final bus = chatCubit.activeTab!.teamBus!;
      bus.markTurnStarted('team-lead');
      unawaited(bus.receive('team-lead'));
      await Future<void>.delayed(Duration.zero);
      await postFrame.flush();
      await pumpSchedulerFrames();

      await waitForPresencePoll(cubit: chatCubit);
      await pumpSchedulerFrames();
      await waitUntil(
        () => presenceCubit.state.presence.containsKey('team-lead'),
      );

      expect(
        presenceCubit.memberPresenceFor('team-lead').workload,
        MemberWorkload.idle,
      );
    });
  });

  group('simple mode session idle/busy (no TeamBus)', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;
    final created = <_SimpleRunningShell>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('it_idle_busy_simple_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      created.clear();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
          final shell = _SimpleRunningShell(executable: executable);
          created.add(shell);
          return shell;
        },
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('send lights working; quiet screen clears it', () async {
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

      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, isEmpty);

      shell.markUserTurnStarted();
      shell.activityTracker.notePtyBytes(
        Uint8List.fromList('working\n'.codeUnits),
      );
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, contains(session.sessionId));

      simulateFingerprintQuietGap(shell);
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, isEmpty);
    });

    test('PTY output alone does not light simple-mode working', () async {
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

      shell.activityTracker.markActive();
      cubit.debugTickIdleWatch();
      expect(
        cubit.state.workingSessionIds,
        isEmpty,
        reason: 'simple mode only lights working after user send',
      );
    });
  });
}
