import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../integration/support/session_idle_busy_harness.dart';
import '../../support/fake_terminal_session.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late SessionRepository repo;
  late ChatCubit cubit;
  late PostFrameTestHarness postFrame;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('it_lazy_spawn_');
    repo = SessionRepository(rootDir: tmp.path);
    postFrame = PostFrameTestHarness();
    cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
      teamById: (teamId) async =>
          teamId == kIdleBusyMixedTeam.id ? kIdleBusyMixedTeam : null,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
    );
  });

  tearDown(() async {
    await postFrame.flush();
    await drainPendingAsyncWork();
    await cubit.close();
    await drainPendingAsyncWork();
    await deleteTempDirBestEffort(tmp);
  });

  test('selecting a declared member with terminal view shown spawns it', () async {
    final opened = await openMixedSessionWithShells(
      cubit: cubit,
      repo: repo,
      postFrame: postFrame,
    );
    final tab = cubit.activeTab!;
    // Model a reclaimed/declared worker: no live shell.
    tab.memberShells.remove('worker-1');
    tab.reclaimedMemberIds.add('worker-1');
    tab.workbenchView = SessionWorkbenchView.terminal;
    tab.persistedSession = (await repo.loadSessions())
        .firstWhere((s) => s.sessionId == opened.sessionId);

    cubit.selectMember('worker-1');
    await drainPendingAsyncWork();

    expect(tab.membersPendingConnect, contains('worker-1'),
      reason: 'selecting a non-running member in the terminal view must spawn it');
  });

  test('setSessionWorkbenchView(terminal) spawns the selected member', () async {
    final opened = await openMixedSessionWithShells(
      cubit: cubit,
      repo: repo,
      postFrame: postFrame,
    );
    final tab = cubit.activeTab!;
    tab.memberShells.remove('team-lead');
    tab.reclaimedMemberIds.add('team-lead');
    tab.workbenchView = SessionWorkbenchView.chat;
    tab.selectedMemberId = 'team-lead';
    tab.persistedSession = (await repo.loadSessions())
        .firstWhere((s) => s.sessionId == opened.sessionId);

    cubit.setSessionWorkbenchView(opened.sessionId, SessionWorkbenchView.terminal);
    await drainPendingAsyncWork();

    expect(tab.membersPendingConnect, contains('team-lead'),
      reason: 'switching to terminal view for a non-running member must spawn it');
  });
}
