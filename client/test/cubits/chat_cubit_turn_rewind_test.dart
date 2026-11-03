import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

import '../support/post_frame_test_harness.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  test('_onTurnEnded on a local simple session checkpoints even when '
      'requiresPtyFallback is false', () async {
    final tmp = await Directory.systemTemp.createTemp('cubit_turn_rewind_');
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: fakeHomeStorage(),
    );
    final attention = AgentAttentionCubit(pruneInterval: null);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
      agentAttentionCubit: attention,
      storage: fakeHomeStorage(),
    );

    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/tmp'),
    ]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      cli: CliTool.claude,
      fixedSessionId: 's',
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
    tab.persistedSession = tab.persistedSession!.withNativeSessionId(
      CliTool.claude.value,
      'native-1',
    );

    attention.applyEvent(
      sessionId: 's',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );

    final checkpoints = <(String, String, String?)>[];
    cubit.onPtyTurnCheckpoint = (sessionId, memberId, nativeSessionId) async {
      checkpoints.add((sessionId, memberId, nativeSessionId));
    };

    cubit.debugOnTurnEnded('s', 'm1');
    await drainPendingAsyncWork();

    expect(checkpoints, [('s', 'm1', 'native-1')]);
    expect(
      attention.state.attentionFor(sessionId: 's', memberId: 'm1'),
      AgentSeatAttention.working,
    );

    await cubit.close();
    await attention.close();
    await postFrame.flush();
    await deleteTempDirBestEffort(tmp);
  });
}
