import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_log.dart';
import 'package:teampilot/services/session_protocol/session_authority.dart';
import 'package:teampilot/services/session_sync/chat_session_activity_source.dart';
import 'package:teampilot/services/session_sync/chat_session_control_port.dart';

import '../../integration/support/session_idle_busy_harness.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  test('publishes one idle attention when a turn completes', () async {
    final tmp = await Directory.systemTemp.createTemp('activity_source_');
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

    final log = AttentionLog(authorityId: 'test-authority', epoch: 1);
    final authority = SessionAuthority(
      authorityId: 'test-authority',
      controlPort: ChatSessionControlPort(cubit),
      attentionLog: log,
    );
    final source = ChatSessionActivitySource(cubit);
    final events = <AttentionEvent>[];
    final sub = authority.attention.listen(events.add);
    source.start(authority);
    addTearDown(() async {
      await sub.cancel();
      source.dispose();
      await cubit.close();
      await attention.close();
      await postFrame.flush();
      await log.close();
      await deleteTempDirBestEffort(tmp);
    });

    final tab = cubit.activeTab!;
    final memberId = tab.memberShells.keys.single;
    final shell = tab.memberShells[memberId]!;
    shell.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
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
    shell.markUserTurnStarted();
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(cubit.state.busySessionIds, contains(session.sessionId));

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
    await Future<void>.delayed(Duration.zero);

    expect(
      cubit.state.sessionActivities[session.sessionId]?.isReadyToChat,
      isTrue,
      reason: 'the local listener must not consume the ready activity',
    );
    final idle = events.where((event) => event.kind == AttentionKind.idle);
    expect(
      idle,
      hasLength(1),
      reason: 'a completed turn must publish exactly one idle attention',
    );
    expect(idle.single.sessionId, session.sessionId);
  });
}
