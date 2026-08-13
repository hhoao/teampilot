import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';
import 'package:teampilot/services/workbench/workbench_strip_navigator.dart';

import '../../support/post_frame_test_harness.dart';

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

  group('WorkbenchStripNavigator', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit chat;
    late WorkbenchCubit workbench;
    late WorkbenchStripNavigator strip;
    late PostFrameTestHarness postFrame;
    late String workspaceId;
    final sessionIds = <String>[];

    Future<void> openSession() async {
      final session = await repo.createSession(
        workspaceId,
        sessionTeam: _team.id,
        rosterMembers: _team.members,
        memberClis: {for (final m in _team.members) m.id: CliTool.claude},
      );
      sessionIds.add(session.sessionId);
      await chat.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: _team,
          member: _team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
      workbench.openSession(
        workspaceId,
        session.sessionId,
        preview: false,
      );
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('workbench_strip_nav_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      sessionIds.clear();
      chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
      );
      workbench = WorkbenchCubit();
      final bridge = WorkbenchChatBridge(workbench: workbench, chat: chat);
      workbench.port = bridge;
      chat.workbenchPort = bridge;
      strip = WorkbenchStripNavigator(workbench: workbench, chat: chat);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      workspaceId = workspace.workspaceId;
      await chat.loadWorkspaceData(repo);
      chat.setActiveWorkspace(workspaceId);
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork(rounds: 8);
      await chat.close();
      await workbench.close();
      await drainPendingAsyncWork(rounds: 8);
      await deleteTempDirBestEffort(tmp);
    });

    test('next/prev no-op when strip is empty', () {
      expect(workbench.centerOrder(workspaceId), isEmpty);
      strip.next();
      strip.previous();
      expect(workbench.centerActiveId(workspaceId), isNull);
      expect(workbench.state.bar(workspaceId).center.landingActive, isTrue);
    });

    test('next/prev wrap across mixed session and diff tabs', () async {
      await openSession();
      await openSession();
      final s0 = WorkbenchTabId.session(sessionIds[0]);
      final s1 = WorkbenchTabId.session(sessionIds[1]);
      final diff = WorkbenchTabId.diffStaged('/tmp/a.dart', staged: false);
      workbench.openDiff(workspaceId, diff, preview: false);
      workbench.activate(workspaceId, s0);
      expect(workbench.centerOrder(workspaceId), [s0, s1, diff]);

      strip.next();
      expect(workbench.centerActiveId(workspaceId), s1);
      expect(chat.activeTab?.info.id, sessionIds[1]);

      strip.next();
      expect(workbench.centerActiveId(workspaceId), diff);

      strip.next();
      expect(workbench.centerActiveId(workspaceId), s0);

      strip.previous();
      expect(workbench.centerActiveId(workspaceId), diff);
    });

    test('focusAt selects 1-based strip ordinal including diffs', () async {
      await openSession();
      final s0 = WorkbenchTabId.session(sessionIds[0]);
      final diff = WorkbenchTabId.diffStaged('/tmp/b.dart', staged: false);
      workbench.openDiff(workspaceId, diff, preview: false);
      workbench.activate(workspaceId, s0);

      strip.focusAt(2);
      expect(workbench.centerActiveId(workspaceId), diff);

      strip.focusAt(1);
      expect(workbench.centerActiveId(workspaceId), s0);
      expect(chat.activeTab?.info.id, sessionIds[0]);
    });

    test('focusAt no-ops when ordinal is out of range', () async {
      await openSession();
      final active = workbench.centerActiveId(workspaceId);
      strip.focusAt(3);
      expect(workbench.centerActiveId(workspaceId), active);
    });

    test('next clears new-chat landing', () async {
      await openSession();
      await openSession();
      final s0 = WorkbenchTabId.session(sessionIds[0]);
      workbench.activate(workspaceId, s0);
      workbench.enterLanding(workspaceId);
      expect(workbench.state.bar(workspaceId).center.landingActive, isTrue);

      // Landing is not a tab: next() activates the first strip tab.
      strip.next();
      expect(workbench.state.bar(workspaceId).center.landingActive, isFalse);
      expect(workbench.centerActiveId(workspaceId), s0);
    });

    test('close(active session) is the session-close-tab command equivalent',
        () async {
      await openSession();
      await openSession();
      expect(chat.tabStore.openTabs, hasLength(2));
      final closing = chat.activeTab?.info.id;
      final active = workbench.centerActiveId(workspaceId);
      await workbench.close(workspaceId, active!);
      await drainPendingAsyncWork();
      await postFrame.flush();
      expect(chat.tabStore.openTabs, hasLength(1));
      expect(chat.activeTab?.info.id, isNot(closing));
    });

    test('enterLanding(activeWorkspaceId) is the session-new-tab command '
        'equivalent', () async {
      await openSession();
      expect(workbench.state.bar(workspaceId).center.landingActive, isFalse);
      workbench.enterLanding(chat.tabStore.activeWorkspaceId);
      expect(workbench.state.bar(workspaceId).center.landingActive, isTrue);
    });
  });
}
