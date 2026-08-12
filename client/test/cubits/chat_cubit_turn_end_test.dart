import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

import '../integration/support/session_idle_busy_harness.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  test('simple cursor: PTY quiet clears the attention working seat', () async {
    final tmp = await Directory.systemTemp.createTemp('cubit_turn_end_');
    final repo = SessionRepository(rootDir: tmp.path);
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
    );

    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/tmp')]);
    final session = (await repo.createSession(workspace.workspaceId, cli: CliTool.cursor)).session;
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
    final shell = tab.memberShells.values.single;
    shell.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    // Stamp working via the cursor agent-status hook (afterAgentResponse),
    // and latch the user turn (submit) so the turn-end edge can fire.
    attention.applyEvent(
      sessionId: session.sessionId,
      memberId: session.sessionId,
      event: const AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'afterAgentResponse',
      ),
      skipPermissions: false,
    );
    shell.markUserTurnStarted();
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(cubit.state.workingSessionIds, contains(session.sessionId));

    // PTY goes quiet → turn-end fallback should clear the seat.
    simulateFingerprintQuietGap(shell);
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();

    expect(
      attention.state.attentionFor(
        sessionId: session.sessionId,
        memberId: session.sessionId,
      ),
      isNull,
    );
    expect(cubit.state.workingSessionIds, isEmpty);

    await cubit.close();
    await attention.close();
    await postFrame.flush();
    await deleteTempDirBestEffort(tmp);
  });
}
