import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../../support/fake_terminal_session.dart';
import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'ChatCubit composition root drives the real scheduler and executor',
    () async {
      final tmp = await Directory.systemTemp.createTemp('launch_composition_');
      addTearDown(() => deleteTempDirBestEffort(tmp));
      final repository = SessionRepository(
        rootDir: tmp.path,
        storage: testHomeStorage,
      );
      final postFrame = PostFrameTestHarness();
      final shells = <FakeTerminalSession>[];
      final cubit = ChatCubit(
        storage: testHomeStorage,
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repository,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final shell = FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
                fs: InMemoryFilesystem(),
              );
              shells.add(shell);
              return shell;
            },
      );
      addTearDown(() async {
        await postFrame.flush();
        await cubit.close();
        for (final shell in shells) {
          shell.dispose();
        }
      });

      final workspace = await repository.createWorkspace([
        const WorkspaceFolder(path: '/work'),
      ]);
      final session = (await repository.createSession(
        workspace.workspaceId,
      )).session;
      await cubit.loadWorkspaceData(repository);

      final status = await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repository,
        ),
      );

      expect(status, isNotNull);
      expect(postFrame.hasPendingCallbacks, isTrue);
      await waitUntil(
        () => shells.isNotEmpty && shells.single.isRunning,
        pump: () async {
          await postFrame.flush();
          await drainPendingAsyncWork();
        },
      );

      expect(shells, hasLength(1));
      expect(shells.single.isRunning, isTrue);
      expect(cubit.activeTab?.membersPendingConnect, isEmpty);
      expect(cubit.isSessionConnecting(session.sessionId), isFalse);
    },
  );
}
