import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';

class _FakeTerminalSession extends TerminalSession {
  _FakeTerminalSession({required super.executable});

  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  bool get isConnecting => false;

  @override
  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    ShellLaunchSpec? shellLaunch,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    BusUserInputRouting? busUserInputRouting,
    String? executableOverride,
  }) {
    _running = true;
    onProcessStarted?.call();
  }

  @override
  void disconnect() => _running = false;

  @override
  void dispose() => _running = false;
}

const _team = TeamProfile(
  id: 'team-a',
  name: 'A',
  members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit session tab navigation commands', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;
    late String workspaceId;
    final sessionIds = <String>[];

    Future<void> openTab() async {
      final session = await repo.createSession(
        workspaceId,
        sessionTeam: _team.id,
        rosterMembers: _team.members,
      );
      sessionIds.add(session.sessionId);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: _team,
          member: _team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
    }

    Future<void> openTabs(int count) async {
      for (var i = 0; i < count; i++) {
        await openTab();
      }
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp(
        'chat_cubit_session_shortcut_',
      );
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      sessionIds.clear();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      workspaceId = workspace.workspaceId;
      await cubit.loadWorkspaceData(repo);
      cubit.setActiveWorkspace(workspaceId);
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork(rounds: 8);
      await cubit.close();
      await drainPendingAsyncWork(rounds: 8);
      await deleteTempDirBestEffort(tmp);
    });

    test('selectNextSessionTab is a no-op with no open tabs', () {
      expect(cubit.state.tabs, isEmpty);
      expect(cubit.state.composeActive, isTrue);

      cubit.selectNextSessionTab();

      expect(cubit.state.activeTabIndex, 0);
      expect(cubit.state.composeActive, isTrue);
      expect(cubit.state.activeSessionId, isNull);
    });

    test('selectPreviousSessionTab is a no-op with no open tabs', () {
      expect(cubit.state.tabs, isEmpty);
      expect(cubit.state.composeActive, isTrue);

      cubit.selectPreviousSessionTab();

      expect(cubit.state.activeTabIndex, 0);
      expect(cubit.state.composeActive, isTrue);
      expect(cubit.state.activeSessionId, isNull);
    });

    test('selectNextSessionTab wraps forward across open session tabs', () async {
      await openTabs(3);
      expect(cubit.state.tabs, hasLength(3));
      expect(cubit.state.activeTabIndex, 2);

      cubit.selectNextSessionTab();
      expect(cubit.state.activeTabIndex, 0);
      expect(cubit.state.activeSessionId, sessionIds[0]);

      cubit.selectNextSessionTab();
      expect(cubit.state.activeTabIndex, 1);
      expect(cubit.state.activeSessionId, sessionIds[1]);

      cubit.selectNextSessionTab();
      expect(cubit.state.activeTabIndex, 2);
      expect(cubit.state.activeSessionId, sessionIds[2]);
    });

    test(
      'selectPreviousSessionTab wraps backward across open session tabs',
      () async {
        await openTabs(3);
        cubit.selectTab(0);
        expect(cubit.state.activeTabIndex, 0);

        cubit.selectPreviousSessionTab();
        expect(cubit.state.activeTabIndex, 2);
        expect(cubit.state.activeSessionId, sessionIds[2]);

        cubit.selectPreviousSessionTab();
        expect(cubit.state.activeTabIndex, 1);
        expect(cubit.state.activeSessionId, sessionIds[1]);

        cubit.selectPreviousSessionTab();
        expect(cubit.state.activeTabIndex, 0);
        expect(cubit.state.activeSessionId, sessionIds[0]);
      },
    );

    test(
      'selectNextSessionTab clears compose landing when open tabs still exist',
      () async {
        await openTabs(3);
        cubit.selectTab(0);
        cubit.enterComposeMode(workspaceId);
        expect(cubit.state.composeActive, isTrue);
        expect(cubit.state.tabs, hasLength(3));
        // Compose preserves the last selected index so navigation resumes
        // from there instead of restarting at 0.
        expect(cubit.state.activeTabIndex, 0);

        cubit.selectNextSessionTab();

        expect(cubit.state.composeActive, isFalse);
        expect(cubit.state.activeTabIndex, 1);
        expect(cubit.state.activeSessionId, sessionIds[1]);
      },
    );

    test(
      'selectPreviousSessionTab clears compose landing when open tabs still exist',
      () async {
        await openTabs(3);
        cubit.selectTab(0);
        cubit.enterComposeMode(workspaceId);
        expect(cubit.state.composeActive, isTrue);
        expect(cubit.state.tabs, hasLength(3));

        cubit.selectPreviousSessionTab();

        expect(cubit.state.composeActive, isFalse);
        expect(cubit.state.activeTabIndex, 2);
        expect(cubit.state.activeSessionId, sessionIds[2]);
      },
    );

    test(
      'closeTab(activeTabIndex) is the session-close-tab command equivalent',
      () async {
        await openTabs(2);
        expect(cubit.state.tabs, hasLength(2));
        final closedSessionId = sessionIds[1];
        expect(cubit.state.activeSessionId, closedSessionId);

        cubit.closeTab(cubit.state.activeTabIndex);

        expect(cubit.state.tabs, hasLength(1));
        expect(cubit.state.activeSessionId, sessionIds[0]);
        expect(
          cubit.state.tabs.any((t) => t.id == closedSessionId),
          isFalse,
        );
      },
    );

    test(
      'enterComposeMode(activeWorkspaceId) is the session-new-tab command '
      'equivalent, and keeps open tabs',
      () async {
        await openTabs(2);
        expect(cubit.state.composeActive, isFalse);

        cubit.enterComposeMode(cubit.tabStore.activeWorkspaceId);

        expect(cubit.state.composeActive, isTrue);
        expect(cubit.state.tabs, hasLength(2));
        expect(cubit.state.activeSessionId, isNull);
      },
    );

    test('selectSessionTabAt jumps to 1-based ordinal', () async {
      await openTabs(3);
      cubit.selectTab(0);

      cubit.selectSessionTabAt(2);

      expect(cubit.state.activeTabIndex, 1);
      expect(cubit.state.activeSessionId, sessionIds[1]);
    });

    test('selectSessionTabAt(10) selects the 10th tab when present', () async {
      await openTabs(10);
      cubit.selectTab(0);

      cubit.selectSessionTabAt(10);

      expect(cubit.state.activeTabIndex, 9);
      expect(cubit.state.activeSessionId, sessionIds[9]);
    });

    test('selectSessionTabAt no-ops when ordinal is out of range', () async {
      await openTabs(2);
      cubit.selectTab(0);

      cubit.selectSessionTabAt(3);

      expect(cubit.state.activeTabIndex, 0);
      expect(cubit.state.activeSessionId, sessionIds[0]);
    });

    test('selectSessionTabAt clears compose landing', () async {
      await openTabs(2);
      cubit.enterComposeMode(workspaceId);
      expect(cubit.state.composeActive, isTrue);

      cubit.selectSessionTabAt(1);

      expect(cubit.state.composeActive, isFalse);
      expect(cubit.state.activeTabIndex, 0);
      expect(cubit.state.activeSessionId, sessionIds[0]);
    });
  });
}
