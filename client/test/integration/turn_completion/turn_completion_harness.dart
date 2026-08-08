import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/post_frame_test_harness.dart';
import '../support/session_idle_busy_harness.dart';

typedef OpenSimpleTurnResult = ({
  String sessionId,
  TerminalSession shell,
  ChatCubit cubit,
  AgentAttentionCubit attention,
});

Future<OpenSimpleTurnResult> openSimpleTurnSession({
  required CliTool cli,
  required SessionRepository repo,
  required PostFrameTestHarness postFrame,
}) async {
  final attention = AgentAttentionCubit(pruneInterval: null);
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
  final session = await repo.createSession(workspace.workspaceId, cli: cli);
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
  await postFrame.flush();
  final tab = cubit.activeTab!;
  final shell = tab.memberShells.values.single;
  shell.activityTracker.latchBootFrameReadyForTest(
    DateTime.now().subtract(const Duration(seconds: 5)),
  );
  return (
    sessionId: session.sessionId,
    shell: shell,
    cubit: cubit,
    attention: attention,
  );
}

void stampWorking(
  AgentAttentionCubit attention,
  String sessionId,
  String memberId,
) {
  attention.applyEvent(
    sessionId: sessionId,
    memberId: memberId,
    event: const AgentStatusEvent(
      state: AgentSeatAttention.working,
      hookEventName: 'afterAgentResponse',
    ),
    skipPermissions: false,
  );
}

void stampDone(
  AgentAttentionCubit attention,
  String sessionId,
  String memberId, {
  required String doneEventName,
}) {
  attention.applyEvent(
    sessionId: sessionId,
    memberId: memberId,
    event: AgentStatusEvent(
      state: AgentSeatAttention.done,
      hookEventName: doneEventName,
    ),
    skipPermissions: false,
  );
}
