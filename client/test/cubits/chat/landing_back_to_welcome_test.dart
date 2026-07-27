import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/workbench/workbench_center_mode.dart';

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
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'dismissNewChat + clearActive yields welcome and keeps tabOrder',
    () async {
      const team = TeamProfile(
        id: 'team-a',
        name: 'A',
        members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
      );
      final tmp = await Directory.systemTemp.createTemp('landing_back_tabs_');
      addTearDown(() async {
        try {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      );

      final postFrame = PostFrameTestHarness();
      final chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chat.close();
      });

      chat.setActiveWorkspace(workspace.workspaceId);
      await chat.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: team,
          member: team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();

      final workbench = WorkbenchCubit();
      addTearDown(workbench.close);
      final sessionTab = WorkbenchTabId.session(session.sessionId);
      workbench.ensureTab(workspace.workspaceId, sessionTab);
      expect(workbench.activeTabId(workspace.workspaceId), sessionTab);

      chat.enterNewChat(workspace.workspaceId);
      expect(chat.state.newChatActive, isTrue);

      final orderBefore = List.of(workbench.tabOrder(workspace.workspaceId));
      chat.dismissNewChat();
      workbench.enterWelcome(workspace.workspaceId);

      expect(chat.state.newChatActive, isFalse);
      expect(workbench.activeTabId(workspace.workspaceId), isNull);
      expect(workbench.welcomeActive(workspace.workspaceId), isTrue);
      expect(workbench.tabOrder(workspace.workspaceId), orderBefore);

      // Runtime path: WorkbenchSessionSync calls syncSessions after compose ends.
      workbench.syncSessions(
        workspace.workspaceId,
        [session.sessionId],
        preferredActiveSessionId: session.sessionId,
        newChatActive: false,
      );
      expect(workbench.activeTabId(workspace.workspaceId), isNull);
      expect(workbench.welcomeActive(workspace.workspaceId), isTrue);
      expect(
        resolveWorkbenchCenterMode(
          newChatActive: chat.state.newChatActive,
          activeTabId: workbench.activeTabId(workspace.workspaceId),
        ),
        WorkbenchCenterMode.welcome,
      );
    },
  );

  test(
    'empty tabs: dismiss + clearActive stays welcome not forced compose',
    () async {
      final tmp = await Directory.systemTemp.createTemp('landing_back_empty_');
      addTearDown(() async {
        try {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);

      final postFrame = PostFrameTestHarness();
      final chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chat.close();
      });

      await chat.loadWorkspaceData(repo);
      chat.setActiveWorkspace(workspace.workspaceId);
      chat.enterNewChat(workspace.workspaceId);
      expect(chat.state.newChatActive, isTrue);
      expect(chat.state.tabs, isEmpty);

      final workbench = WorkbenchCubit();
      addTearDown(workbench.close);

      chat.dismissNewChat();
      workbench.enterWelcome(workspace.workspaceId);

      expect(chat.state.newChatActive, isFalse);
      expect(workbench.activeTabId(workspace.workspaceId), isNull);
      expect(workbench.welcomeActive(workspace.workspaceId), isTrue);
      expect(
        resolveWorkbenchCenterMode(
          newChatActive: chat.state.newChatActive,
          activeTabId: workbench.activeTabId(workspace.workspaceId),
        ),
        WorkbenchCenterMode.welcome,
      );

      // Contrast: exitNewChat with empty tabs re-enters compose.
      chat.enterNewChat(workspace.workspaceId);
      chat.exitNewChat();
      expect(chat.state.newChatActive, isTrue);
    },
  );
}
