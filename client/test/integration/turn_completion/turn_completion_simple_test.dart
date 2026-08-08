@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

import '../../support/post_frame_test_harness.dart';
import '../support/integration_test_setup.dart';
import '../support/session_idle_busy_harness.dart';
import 'turn_completion_harness.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  const allCli = [
    CliTool.claude,
    CliTool.flashskyai,
    CliTool.codex,
    CliTool.opencode,
    CliTool.cursor,
  ];

  const doneEvent = {
    CliTool.claude: 'Stop',
    CliTool.flashskyai: 'Stop',
    CliTool.codex: 'Stop',
    CliTool.opencode: 'session.idle',
    CliTool.cursor: 'stop',
  };

  for (final cli in allCli) {
    test('$cli: done event clears working', () async {
      final tmp = await Directory.systemTemp.createTemp('tc_simple_');
      final repo = SessionRepository(rootDir: tmp.path);
      final postFrame = PostFrameTestHarness();
      final opened = await openSimpleTurnSession(
        cli: cli,
        repo: repo,
        postFrame: postFrame,
      );
      stampWorking(opened.attention, opened.sessionId, opened.sessionId);
      await drainPendingAsyncWork();
      expect(opened.cubit.state.workingSessionIds, contains(opened.sessionId));

      stampDone(
        opened.attention,
        opened.sessionId,
        opened.sessionId,
        doneEventName: doneEvent[cli]!,
      );
      await drainPendingAsyncWork();
      expect(opened.cubit.state.workingSessionIds, isEmpty);
      await opened.cubit.close();
      await opened.attention.close();
      await deleteTempDirBestEffort(tmp);
    });

    test('$cli: PTY-quiet fallback clears working only for fallback CLIs', () async {
      final tmp = await Directory.systemTemp.createTemp('tc_simple_');
      final repo = SessionRepository(rootDir: tmp.path);
      final postFrame = PostFrameTestHarness();
      final opened = await openSimpleTurnSession(
        cli: cli,
        repo: repo,
        postFrame: postFrame,
      );
      stampWorking(opened.attention, opened.sessionId, opened.sessionId);
      opened.shell.markUserTurnStarted();
      opened.cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();
      expect(opened.cubit.state.workingSessionIds, contains(opened.sessionId));

      simulateFingerprintQuietGap(opened.shell);
      opened.cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();

      final shouldClear = {
        CliTool.claude: false,
        CliTool.flashskyai: false,
        CliTool.codex: false,
        CliTool.opencode: false,
        CliTool.cursor: true,
      }[cli]!;
      expect(
        opened.cubit.state.workingSessionIds.isEmpty,
        shouldClear,
        reason: '$cli requiresPtyFallback=$shouldClear',
      );
      await opened.cubit.close();
      await opened.attention.close();
      await deleteTempDirBestEffort(tmp);
    });
  }

  test('PTY-quiet fallback never clears a waiting seat', () async {
    final tmp = await Directory.systemTemp.createTemp('tc_wait_');
    final repo = SessionRepository(rootDir: tmp.path);
    final postFrame = PostFrameTestHarness();
    final opened = await openSimpleTurnSession(
      cli: CliTool.cursor,
      repo: repo,
      postFrame: postFrame,
    );
    // waiting (permission) seat
    opened.attention.applyEvent(
      sessionId: opened.sessionId,
      memberId: opened.sessionId,
      event: const AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
      ),
      skipPermissions: false,
    );
    opened.shell.markUserTurnStarted();
    await drainPendingAsyncWork();
    simulateFingerprintQuietGap(opened.shell);
    opened.cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(
      opened.attention.state.attentionFor(
        sessionId: opened.sessionId,
        memberId: opened.sessionId,
      ),
      AgentSeatAttention.waiting,
    );
    await opened.cubit.close();
    await opened.attention.close();
    await deleteTempDirBestEffort(tmp);
  });
}
