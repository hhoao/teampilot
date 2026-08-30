import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';

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

  group('ChatCubit workspace working scope', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;
    final created = <_RunningFakeSession>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chat_ws_working_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      created.clear();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
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
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test(
      'switching workspace does not drop background working sessions',
      () async {
        final workspaceA = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp/a'),
        ]);
        final workspaceB = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp/b'),
        ]);
        final session = (await repo.createSession(workspaceA.workspaceId)).session;
        await cubit.loadWorkspaceData(repo);

        cubit.setActiveWorkspace(workspaceA.workspaceId);
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspaceA,
            repo: repo,
            connectImmediately: false,
          ),
        );
        await drainPendingAsyncWork();

        final shell = created.single;
        shell.markUserTurnStarted();
        shell.activityTracker.isWorking;
        shell.activityTracker.markActive();
        cubit.debugTickIdleWatch();
        await drainPendingAsyncWork();
        expect(
          cubit.state.busySessionIds,
          contains(session.sessionId),
        );

        cubit.setActiveWorkspace(workspaceB.workspaceId);
        cubit.debugTickIdleWatch();
        await drainPendingAsyncWork();

        expect(
          cubit.state.busySessionIds,
          contains(session.sessionId),
          reason:
              'background workspace session must stay in busySessionIds',
        );
      },
    );
  });
}
