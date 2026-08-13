@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../support/post_frame_test_harness.dart';
import '../support/connected_recording_shell.dart';
import '../support/integration_test_setup.dart';
import '../support/session_idle_busy_harness.dart';

const kCursorMixedTeam = TeamProfile(
  id: 'tc-cursor-mixed',
  name: 'Cursor Mixed',
  teamMode: TeamMode.mixed,
  cli: CliTool.cursor,
  members: [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    TeamMemberConfig(id: 'worker-1', name: 'developer', cli: CliTool.cursor),
  ],
);

Future<({String sessionId, ChatCubit cubit})>
openCursorMixedSession({
  required ChatCubit cubit,
  required SessionRepository repo,
  required PostFrameTestHarness postFrame,
}) async {
  final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/tmp')]);
  final session = (await repo.createSession(
    workspace.workspaceId,
    sessionTeam: kCursorMixedTeam.id,
    rosterMembers: kCursorMixedTeam.members,
    memberClis: {
      for (final m in kCursorMixedTeam.members) m.id: CliTool.cursor,
    },
  )).session;
  await cubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      team: kCursorMixedTeam,
      member: kCursorMixedTeam.members.first,
      repo: repo,
      connectImmediately: false,
    ),
  );
  await drainPendingAsyncWork();
  await postFrame.flush();

  final tab = cubit.activeTab!;
  final bus = tab.teamBus!;
  final workerShell = await ConnectedRecordingShell.connect();
  tab.memberShells['worker-1'] = workerShell.session;
  final bootAt = DateTime.now().subtract(const Duration(seconds: 5));
  workerShell.session.activityTracker.latchBootFrameReadyForTest(bootAt);
  bus.markMemberRunning('worker-1');
  cubit.pushPresenceTarget();
  await postFrame.flush();
  await pumpSchedulerFrames();

  return (sessionId: session.sessionId, cubit: cubit);
}

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test('mixed cursor: /idle ends bus turn and clears working', () async {
    final tmp = await Directory.systemTemp.createTemp('tc_mixed_');
    final repo = SessionRepository(rootDir: tmp.path);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
      agentAttentionCubit: AgentAttentionCubit(pruneInterval: null),
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              RunningConnectedFakeShell(executable: executable),
    );

    final opened = await openCursorMixedSession(
      cubit: cubit,
      repo: repo,
      postFrame: postFrame,
    );
    final bus = cubit.activeTab!.teamBus!;

    bus.markTurnStarted('worker-1');
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(bus.isMemberInTurn('worker-1'), isTrue);
    expect(cubit.state.workingSessionIds, contains(opened.sessionId));

    // Cursor stop hook POSTs /idle → bus turn must end (push CLI).
    final mcp = cubit.teammateBusMcpEndpointForSession(opened.sessionId)!;
    await postMemberIdle(
      idleEndpointFromMcp(mcp),
      'worker-1',
      sessionId: opened.sessionId,
    );

    await drainPendingAsyncWork();
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(bus.isMemberInTurn('worker-1'), isFalse);
    expect(cubit.state.workingSessionIds, isEmpty);

    await cubit.close();
    await deleteTempDirBestEffort(tmp);
  });

  test('mixed claude: /idle is a no-op while parked (turn ends on park)', () async {
    final tmp = await Directory.systemTemp.createTemp('tc_mixed_');
    final repo = SessionRepository(rootDir: tmp.path);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
      agentAttentionCubit: AgentAttentionCubit(pruneInterval: null),
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              RunningConnectedFakeShell(executable: executable),
    );

    final opened = await openMixedSessionWithShells(
      cubit: cubit,
      repo: repo,
      postFrame: postFrame,
    );
    final bus = cubit.activeTab!.teamBus!;
    bus.markMemberRunning('team-lead');
    bus.markTurnStarted('team-lead');
    await drainPendingAsyncWork();
    expect(bus.isMemberInTurn('team-lead'), isTrue);

    // Park the member in wait_for_message.
    unawaited(bus.receive('team-lead'));
    await Future<void>.delayed(Duration.zero);
    expect(bus.isWaitingForMessage('team-lead'), isTrue);
    // The turn has already ended via park; /idle must not double-end it.
    expect(bus.isMemberInTurn('team-lead'), isFalse);

    final mcp = cubit.teammateBusMcpEndpointForSession(opened.sessionId)!;
    await postMemberIdle(
      idleEndpointFromMcp(mcp),
      'team-lead',
      sessionId: opened.sessionId,
    );
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    // Still not in turn, no crash, no re-activation.
    expect(bus.isMemberInTurn('team-lead'), isFalse);

    await cubit.close();
    await deleteTempDirBestEffort(tmp);
  });
}
