import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';

/// Running fake so the non-bus idle-watch branch does not skip it.
class _RunningFakeSession extends TerminalSession {
  _RunningFakeSession({required super.executable});

  @override
  bool get isRunning => true;

  @override
  void dispose() {}
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit simple-mode working indicator', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;
    final created = <_RunningFakeSession>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chat_simple_working_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      created.clear();
      cubit = ChatCubit(
        executableResolver: () => 'true',
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

    test('send lights working; screen going quiet clears it', () async {
      final project = await repo.createProject('/tmp', teamId: '');
      final session = await repo.createSession(project.projectId);
      await cubit.loadProjectData(repo);

      await cubit.openSessionTab(
        session,
        repo: repo,
        connectImmediately: false,
      );
      expect(cubit.state.tabs.length, 1);
      final shell = created.single;

      // Idle before any send: not working.
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, isEmpty);

      // Send → turn starts; agent output makes the activity tracker active.
      shell.markUserTurnStarted();
      shell.activityTracker.isWorking; // arm past the boot-quiet window
      shell.activityTracker.markActive();
      cubit.debugTickIdleWatch();
      expect(
        cubit.state.workingSessionIds,
        contains(session.sessionId),
        reason: 'a send should light the working indicator',
      );

      // Screen goes quiet (last output older than the idle window) → falling
      // edge clears the turn.
      shell.activityTracker.markActive(
        DateTime.now().subtract(const Duration(seconds: 5)),
      );
      cubit.debugTickIdleWatch();
      expect(cubit.state.workingSessionIds, isEmpty);
    });

    test('real 1s idle-watch timer is running for a simple-mode tab', () async {
      final project = await repo.createProject('/tmp', teamId: '');
      final session = await repo.createSession(project.projectId);
      await cubit.loadProjectData(repo);

      await cubit.openSessionTab(
        session,
        repo: repo,
        connectImmediately: false,
      );
      final shell = created.single;

      shell.markUserTurnStarted();
      shell.activityTracker.isWorking; // arm
      shell.activityTracker.markActive();

      // No manual tick — rely on the periodic timer started at tab open.
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(
        cubit.state.workingSessionIds,
        contains(session.sessionId),
        reason: 'ensureIdleWatch must start the periodic timer at tab open',
      );
    });
  });
}
