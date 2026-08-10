import 'dart:io';

import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

void _registerTempCubitCleanup({
  required Directory tmp,
  required ChatCubit cubit,
  PostFrameTestHarness? postFrame,
}) {
  addTearDown(() async {
    if (postFrame != null) {
      await postFrame.flush();
    }
    await drainPendingAsyncWork();
    await cubit.close();
    try {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows CI may retain directory handles briefly after bus teardown.
    }
  });
}

class _FakeTerminalSession extends TerminalSession {
  _FakeTerminalSession({required super.executable});

  var _running = false;
  var _connecting = false;
  final connectedMembers = <String>[];
  final connectedSessionTeams = <String?>[];

  @override
  bool get isRunning => _running || _connecting;

  @override
  bool get isConnecting => _connecting;

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
    _connecting = true;
    final member = shellLaunch?.launchContext.member;
    if (member != null) {
      connectedMembers.add(member.id);
    }
    connectedSessionTeams.add(shellLaunch?.sessionTeam);
    _connecting = false;
    _running = true;
    onProcessStarted?.call();
  }

  @override
  void disconnect() {
    _running = false;
    _connecting = false;
  }

  @override
  void dispose() {
    _running = false;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  setUp(() => composeDraftCache.clear());
  tearDown(tearDownTestAppStorage);

  group('ChatCubit team session scope', () {
    late ChatCubit cubit;

    setUp(() {
      cubit = ChatCubit(
        executableResolver: _executable,
        automationRepository: testAutomationRepository(),
      );
    });

    tearDown(() async {
      await cubit.close();
    });

    test('visible lists mirror full data when scope is off', () {
      const workspaceId = 'p1';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: workspaceId,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: workspaceId,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'team-a',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );
      expect(cubit.state.workspaces.length, 1);
      expect(cubit.state.visibleWorkspaces, cubit.state.workspaces);
      expect(cubit.state.visibleSessions, cubit.state.sessions);
    });

    test('scope on filters sessions and workspaces by selected team id', () {
      const pA = 'p-a';
      const pB = 'p-b';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: pA,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
          Workspace(
            workspaceId: pB,
            folders: [WorkspaceFolder(path: '/b')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s3'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: pA,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's2',
            workspaceId: pA,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'tid-2',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's3',
            workspaceId: pB,
            folders: [WorkspaceFolder(path: '/b')],
            sessionTeam: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: 'tid-1',
      );

      expect(cubit.state.sessions.length, 3);
      expect(
        cubit.state.visibleSessions.map((e) => e.sessionId).toList()..sort(),
        ['s1', 's3'],
      );
      expect(cubit.state.visibleWorkspaces.map((e) => e.workspaceId).toSet(), {
        'p-a',
        'p-b',
      });
    });

    test('scope on with no selected team shows personal sessions only', () {
      const pid = 'p1';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'tid',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );
      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: null,
      );
      expect(cubit.state.visibleSessions, isEmpty);
      expect(cubit.state.visibleWorkspaces.map((e) => e.workspaceId).toList(), [
        pid,
      ]);
    });

    test('changing scope or team id updates visible lists', () {
      const pid = 'p1';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'alpha',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's2',
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'beta',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: 'alpha',
      );
      expect(cubit.state.visibleSessions.single.sessionId, 's1');

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: 'beta',
      );
      expect(cubit.state.visibleSessions.single.sessionId, 's2');

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: false,
        selectedTeamId: 'beta',
      );
      expect(cubit.state.visibleSessions.length, 2);
    });
  });

  group('connectWorkspaceSession', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      setUpTestAppStorage();
      tmp = Directory(AppStorage.paths.basePath);
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
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
        WorkspaceFolder(path: '/tmp'),
      ]);
      await cubit.loadWorkspaceData(repo);
      cubit.setActiveWorkspace(workspace.workspaceId);
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      tearDownTestAppStorage();
    });

    test('materializes tab when selectedMemberId is empty', () async {
      const team = TeamProfile(
        id: 'team-a',
        name: 'A',
        members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
      );
      expect(cubit.state.selectedMemberId, '');
      await cubit.connectWorkspaceSession(TeamSessionConnect(team));
      await postFrame.flush();
      await drainPendingAsyncWork();
      expect(cubit.tabStore.openTabs.length, 1);
      expect(cubit.state.selectedMemberId, 'm-lead');
    });

    test(
      'personal connect materializes first session when tabs empty',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp/personal-connect'),
        ]);
        await cubit.loadWorkspaceData(repo);
        cubit.setActiveWorkspace(workspace.workspaceId);
        expect(cubit.tabStore.openTabs, isEmpty);

        await cubit.connectWorkspaceSession(
          PersonalSessionConnect(workspaceId: workspace.workspaceId),
          repo: repo,
        );
        await postFrame.flush();
        await drainPendingAsyncWork();

        expect(cubit.tabStore.openTabs.length, 1);
        expect(cubit.state.sessions.single.sessionTeam, '');
      },
    );

    test('uses team cli executable for member shell', () async {
      final executables = <String>[];
      final cubit = ChatCubit(
        executableResolver: () => 'flashskyai',
        automationRepository: testAutomationRepository(),
        cliExecutableResolver: (cli) =>
            cli == CliTool.claude ? '/opt/bin/claude' : 'flashskyai',
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              executables.add(executable);
              return _FakeTerminalSession(executable: executable);
            },
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(cubit.close);
      const team = TeamProfile(
        id: 'team-a',
        name: 'A',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
      );

      await cubit.connectWorkspaceSession(TeamSessionConnect(team));
      await postFrame.flush();

      expect(executables, contains('/opt/bin/claude'));
    });

    test(
      'requestOpenSession stages tab and connecting before async prep completes',
      () async {
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_stage_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        await cubit.loadWorkspaceData(repo);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspace,
            repo: repo,
          ),
        );

        expect(cubit.tabStore.openTabs, hasLength(1));
        expect(cubit.state.activeSessionId, session.sessionId);
        expect(cubit.isSessionConnecting(session.sessionId), isTrue);
      },
    );

    test(
      'requestCreateAndOpenSession stages tab before disk persist completes',
      () async {
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_create_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
        ]);
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        await cubit.loadWorkspaceData(repo);

        await cubit.requestCreateAndOpenSession(
          SessionCreateRequest(
            workspace: workspace,
            isPersonal: true,
            repo: repo,
            cli: CliTool.claude,
          ),
        );

        expect(cubit.tabStore.openTabs, hasLength(1));
        expect(cubit.state.activeSessionId, isNotEmpty);
        expect(cubit.isSessionConnecting(cubit.state.activeSessionId!), isTrue);
        expect(cubit.state.sessions, hasLength(1));
      },
    );

    test(
      'requestOpenSession stages team tab before async readiness check',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_team_stage_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        await cubit.loadWorkspaceData(repo);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspace,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );

        expect(cubit.tabStore.openTabs, hasLength(1));
        expect(cubit.state.activeSessionId, session.sessionId);
        expect(cubit.isSessionConnecting(session.sessionId), isTrue);
      },
    );

    test(
      'openSessionTab starts all members when auto-launch enabled',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
                final fake = _FakeTerminalSession(executable: executable);
                fakeSessions.add(fake);
                return fake;
              },
          postFrameScheduler: postFrame.scheduler,
          autoLaunchAllMembersOnConnect: () => true,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.tabStore.openTabs.length, 1);
        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-lead'), isTrue);
        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-dev'), isTrue);
        expect(cubit.state.selectedMemberId, 'm-lead');
        expect(fakeSessions, hasLength(2));
        expect(
          fakeSessions.map((shell) => shell.connectedSessionTeams.single),
          everyElement('team-a-1'),
        );
      },
    );

    test(
      'closeTabsForWorkspace counts and terminates a workspace\'s open tabs',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_close_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspaceA = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final workspaceB = await repo.createWorkspace([
          WorkspaceFolder(path: '/b'),
        ]);
        final sessionA = await repo.createSession(
          workspaceA.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final sessionB = await repo.createSession(
          workspaceB.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        // Runtime registry stamps each staged tab with the active workspace, so
        // switch the foreground workspace to match the session being opened.
        cubit.setActiveWorkspace(workspaceA.workspaceId);
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: sessionA,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        cubit.setActiveWorkspace(workspaceB.workspaceId);
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: sessionB,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.tabStore.openTabs.length, 2);
        expect(cubit.openTabCountForWorkspace(workspaceA.workspaceId), 1);
        expect(cubit.openTabCountForWorkspace(workspaceB.workspaceId), 1);
        expect(cubit.openTabCountForWorkspace('no-such-workspace'), 0);

        cubit.closeTabsForWorkspace(workspaceA.workspaceId);

        expect(cubit.tabStore.openTabs.length, 1);
        expect(cubit.openTabCountForWorkspace(workspaceA.workspaceId), 0);
        expect(cubit.openTabCountForWorkspace(workspaceB.workspaceId), 1);
      },
    );

    test(
      'enterNewChat keeps open tabs and clears active session',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_compose_',
        );
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
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        final workbench = WorkbenchCubit();
        addTearDown(workbench.close);
        final bridge = WorkbenchChatBridge(workbench: workbench, chat: cubit);
        workbench.port = bridge;
        cubit.workbenchPort = bridge;
        cubit.onSessionTabOpened = bridge.onSessionTabOpened;

        cubit.setActiveWorkspace(workspace.workspaceId);
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.tabStore.openTabs, hasLength(1));
        expect(
          workbench.state.bar(workspace.workspaceId).center.landingActive,
          isFalse,
        );
        expect(cubit.state.activeSessionId, session.sessionId);

        // Entering new-chat routes through the port to the bar landing.
        cubit.enterNewChat(workspace.workspaceId);
        await drainPendingAsyncWork();

        expect(cubit.tabStore.openTabs, hasLength(1));
        expect(
          workbench.state.bar(workspace.workspaceId).center.landingActive,
          isTrue,
        );
        expect(cubit.state.activeSessionId, isNull);
        expect(cubit.openTabCountForWorkspace(workspace.workspaceId), 1);

        // Re-selecting the session exits the landing.
        workbench.activate(
          workspace.workspaceId,
          WorkbenchTabId.session(session.sessionId),
        );
        await drainPendingAsyncWork();

        expect(
          workbench.state.bar(workspace.workspaceId).center.landingActive,
          isFalse,
        );
        expect(cubit.state.activeSessionId, session.sessionId);
      },
    );

    test(
      'setActiveWorkspace re-syncs the foreground session from the bar',
      () async {
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
        );
        addTearDown(cubit.close);
        final workbench = WorkbenchCubit();
        addTearDown(workbench.close);
        final bridge = WorkbenchChatBridge(workbench: workbench, chat: cubit);
        workbench.port = bridge;
        cubit.workbenchPort = bridge;
        cubit.onSessionTabOpened = bridge.onSessionTabOpened;

        ChatTab tab(String id) => ChatTab(
          info: ChatTabInfo(id: id, title: id, subtitle: ''),
          cliTeamName: id,
        );

        // Workspace A: two open session tabs, bar active on the second.
        cubit.setActiveWorkspace('ws-a');
        cubit.tabStore.registerSession(tab('a-1'));
        cubit.tabStore.registerSession(tab('a-2'));
        bridge.onSessionTabOpened('ws-a', 'a-1');
        bridge.onSessionTabOpened('ws-a', 'a-2');

        // Workspace B: two open session tabs, bar active on the second.
        cubit.setActiveWorkspace('ws-b');
        cubit.tabStore.registerSession(tab('b-1'));
        cubit.tabStore.registerSession(tab('b-2'));
        bridge.onSessionTabOpened('ws-b', 'b-1');
        bridge.onSessionTabOpened('ws-b', 'b-2');

        expect(workbench.centerActiveId('ws-a')?.id, 'a-2');
        expect(workbench.centerActiveId('ws-b')?.id, 'b-2');

        // Switching to ws-b mirrors ws-b's bar center-active session.
        cubit.setActiveWorkspace('ws-b');
        expect(cubit.state.activeSessionId, 'b-2');

        // Switching back to ws-a mirrors ws-a's bar center-active session.
        cubit.setActiveWorkspace('ws-a');
        expect(cubit.state.activeSessionId, 'a-2');
      },
    );

    test(
      'deleteSession of the active open tab enters new-chat landing',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_delete_active_',
        );
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
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        final workbench = WorkbenchCubit();
        addTearDown(workbench.close);
        final bridge = WorkbenchChatBridge(workbench: workbench, chat: cubit);
        workbench.port = bridge;
        cubit.workbenchPort = bridge;
        cubit.onSessionTabOpened = bridge.onSessionTabOpened;

        await cubit.loadWorkspaceData(repo);
        cubit.setActiveWorkspace(workspace.workspaceId);
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.tabStore.openTabs, hasLength(1));
        expect(
          workbench.state.bar(workspace.workspaceId).center.landingActive,
          isFalse,
        );
        expect(cubit.state.activeSessionId, session.sessionId);

        await cubit.deleteSession(repo, session.sessionId);
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.tabStore.openTabs, isEmpty);
        // Closing the last center tab returns the workspace to landing.
        expect(
          workbench.state.bar(workspace.workspaceId).center.landingActive,
          isTrue,
        );
        expect(cubit.state.activeSessionId, isNull);
        expect(
          cubit.state.sessions.any((s) => s.sessionId == session.sessionId),
          isFalse,
        );
      },
    );

    test(
      'deleteSession clears the cached session compose draft',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_draft_clear_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: '',
          rosterMembers: const [],
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.loadWorkspaceData(repo);
        composeDraftCache.setSessionDraft(session.sessionId, 'in progress');

        await cubit.deleteSession(repo, session.sessionId);
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(composeDraftCache.sessionDraft(session.sessionId), isNull);
      },
    );

    test(
      'deleteWorkspace clears the cached landing compose draft',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_workspace_draft_clear_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.loadWorkspaceData(repo);
        composeDraftCache.setLandingDraft(workspace.workspaceId, 'draft');

        await cubit.deleteWorkspace(repo, workspace.workspaceId);
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(composeDraftCache.landingDraft(workspace.workspaceId), isNull);
      },
    );

    test(
      'connectSession auto-launch does not reconnect queued member shells',
      () async {
        final scheduled = <void Function()>[];
        final fakeSessions = <_FakeTerminalSession>[];
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
                final fake = _FakeTerminalSession(executable: executable);
                fakeSessions.add(fake);
                return fake;
              },
          postFrameScheduler: scheduled.add,
          autoLaunchAllMembersOnConnect: () => true,
        );
        addTearDown(cubit.close);
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp/auto-launch'),
        ]);
        await cubit.loadWorkspaceData(repo);
        cubit.setActiveWorkspace(workspace.workspaceId);

        await cubit.connectWorkspaceSession(TeamSessionConnect(team));
        await drainPendingAsyncWork();
        await drainPostFrameQueue(scheduled);

        final connectedMembers = fakeSessions
            .expand((session) => session.connectedMembers)
            .toList();
        expect(connectedMembers.where((id) => id == 'm-lead'), hasLength(1));
        expect(connectedMembers.where((id) => id == 'm-dev'), hasLength(1));
        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-lead'), isTrue);
        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-dev'), isTrue);
      },
    );

    test(
      'mixed openSessionTab seeds member shell with member cli executable',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.mixed,
          members: [
            TeamMemberConfig(
              id: 'm-lead',
              name: 'team-lead',
              cli: CliTool.claude,
            ),
          ],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_mixed_cli_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'flashskyai',
          automationRepository: testAutomationRepository(),
          cliExecutableResolver: (cli) =>
              cli == CliTool.claude ? 'claude' : 'flashskyai',
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
                final fake = _FakeTerminalSession(executable: executable);
                fakeSessions.add(fake);
                return fake;
              },
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members.first,
            repo: repo,
            connectImmediately: false,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(fakeSessions, hasLength(1));
        expect(fakeSessions.single.executable, 'claude');
      },
    );

    test('mixed openSessionTab auto-connects team-lead', () async {
      final fakeSessions = <_FakeTerminalSession>[];
      const team = TeamProfile(
        id: 'team-a',
        name: 'A',
        teamMode: TeamMode.mixed,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'm-dev', name: 'developer'),
        ],
      );
      final tmp = await Directory.systemTemp.createTemp(
        'chat_cubit_mixed_lead_connect_',
      );
      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,

        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      );
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final fake = _FakeTerminalSession(executable: executable);
              fakeSessions.add(fake);
              return fake;
            },
        postFrameScheduler: postFrame.scheduler,
      );
      _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: team,
          member: team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.tabStore.openTabs.length, 1);
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'team-lead'), isTrue);
      expect(
        fakeSessions.expand((s) => s.connectedMembers),
        contains('team-lead'),
      );
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-dev'), isFalse);
    });

    test(
      'mixed openSessionTab does not connect non-lead until user connect',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          teamMode: TeamMode.mixed,
          members: [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_mixed_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
                final fake = _FakeTerminalSession(executable: executable);
                fakeSessions.add(fake);
                return fake;
              },
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members[1],
            repo: repo,
            connectImmediately: true,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.tabStore.openTabs.length, 1);
        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'team-lead'), isFalse);
        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-dev'), isFalse);
        expect(fakeSessions.expand((s) => s.connectedMembers), isEmpty);

        await cubit.connectWorkspaceSession(
          TeamSessionConnect(team),
          repo: repo,
        );
        await postFrame.flush();

        expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'm-dev'), isTrue);
        expect(
          fakeSessions.expand((s) => s.connectedMembers),
          contains('m-dev'),
        );
      },
    );

    test(
      'openMemberTab ignores duplicate taps while member connect is pending',
      () async {
        final scheduled = <void Function()>[];
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
                final fake = _FakeTerminalSession(executable: executable);
                fakeSessions.add(fake);
                return fake;
              },
          postFrameScheduler: scheduled.add,
        );
        addTearDown(cubit.close);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        await drainPendingAsyncWork();
        await drainPostFrameQueue(scheduled);
        scheduled.clear();

        await cubit.openMemberTab(team, team.members[1]);
        expect(scheduled, hasLength(1));

        await cubit.openMemberTab(team, team.members[1]);
        expect(scheduled, hasLength(1));

        await drainPostFrameQueue(scheduled);

        expect(
          fakeSessions
              .expand((s) => s.connectedMembers)
              .where((id) => id == 'm-dev'),
          hasLength(1),
        );
      },
    );

    test(
      'openMemberTab reuses existing team workspace when workspace cwd is set',
      () async {
        const team = TeamProfile(
          id: 'team-default',
          name: 'Default Team',
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_materialize_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        const workspacePath = '/tmp/default-team-workspace';
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: workspacePath),
        ], display: 'Default Team');
        await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );

        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.loadWorkspaceData(repo);
        expect(cubit.state.workspaces, hasLength(1));

        await cubit.openMemberTab(
          team,
          team.members.first,
          repo: repo,
          workspaceCwd: workspacePath,
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.state.workspaces, hasLength(1));
        expect(cubit.state.workspaces.single.firstFolderPath, workspacePath);
        expect(cubit.tabStore.openTabs, hasLength(1));
      },
    );
  });
}
