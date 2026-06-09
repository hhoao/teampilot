import 'dart:io';

import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';


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
    BusUserInputRouting? busUserInputRouting,
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
  tearDown(tearDownTestAppStorage);

  group('ChatCubit team session scope', () {
    late ChatCubit cubit;

    setUp(() {
      cubit = ChatCubit(executableResolver: _executable);
    });

    tearDown(() async {
      await cubit.close();
    });

    test('visible lists mirror full data when scope is off', () {
      const projectId = 'p1';
      cubit.ingestProjectSessionSnapshot(
        projects: const [
          AppProject(
            projectId: projectId,
            primaryPath: '/a',
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1'],
          ),
        ],
        sessions: const [
          AppSession(
            sessionId: 's1',
            projectId: projectId,
            primaryPath: '/a',
            sessionTeam: 'team-a',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );
      expect(cubit.state.projects.length, 1);
      expect(cubit.state.visibleProjects, cubit.state.projects);
      expect(cubit.state.visibleSessions, cubit.state.sessions);
    });

    test('scope on filters sessions and projects by selected team id', () {
      const pA = 'p-a';
      const pB = 'p-b';
      cubit.ingestProjectSessionSnapshot(
        projects: const [
          AppProject(
            projectId: pA,
            primaryPath: '/a',
            teamId: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
          AppProject(
            projectId: pB,
            primaryPath: '/b',
            teamId: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s3'],
          ),
        ],
        sessions: const [
          AppSession(
            sessionId: 's1',
            projectId: pA,
            primaryPath: '/a',
            sessionTeam: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's2',
            projectId: pA,
            primaryPath: '/a',
            sessionTeam: 'tid-2',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's3',
            projectId: pB,
            primaryPath: '/b',
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
      expect(cubit.state.visibleProjects.map((e) => e.projectId).toSet(), {
        'p-a',
        'p-b',
      });
    });

    test('scope on with no selected team yields empty visible lists', () {
      const pid = 'p1';
      cubit.ingestProjectSessionSnapshot(
        projects: const [
          AppProject(
            projectId: pid,
            primaryPath: '/a',
            teamId: 'tid',
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1'],
          ),
        ],
        sessions: const [
          AppSession(
            sessionId: 's1',
            projectId: pid,
            primaryPath: '/a',
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
      expect(cubit.state.visibleProjects, isEmpty);
    });

    test('changing scope or team id updates visible lists', () {
      const pid = 'p1';
      cubit.ingestProjectSessionSnapshot(
        projects: const [
          AppProject(
            projectId: pid,
            primaryPath: '/a',
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
        ],
        sessions: const [
          AppSession(
            sessionId: 's1',
            projectId: pid,
            primaryPath: '/a',
            sessionTeam: 'alpha',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's2',
            projectId: pid,
            primaryPath: '/a',
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

  group('connectSession', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tmp = await Directory.systemTemp.createTemp('chat_conn_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('materializes tab when selectedMemberId is empty', () async {
      const team = TeamConfig(
        id: 'team-a',
        name: 'A',
        members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
      );
      expect(cubit.state.selectedMemberId, '');
      await cubit.connectSession(team);
      await postFrame.flush();
      await drainPendingAsyncWork();
      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.selectedMemberId, 'm-lead');
    });

    test('uses team cli executable for member shell', () async {
      final executables = <String>[];
      final cubit = ChatCubit(
        executableResolver: () => 'flashskyai',
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
      const team = TeamConfig(
        id: 'team-a',
        name: 'A',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
      );

      await cubit.connectSession(team);
      await postFrame.flush();

      expect(executables, contains('/opt/bin/claude'));
    });

    test(
      'openSessionTab starts all members when auto-launch enabled',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        final project = await repo.createProject('/tmp', teamId: '');
        final session = await repo.createSession(
          project.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
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
        addTearDown(cubit.close);

        await cubit.openSessionTab(
          session,
          team: team,
          member: team.members.first,
          repo: repo,
        );
        await postFrame.flush();

        expect(cubit.state.tabs.length, 1);
        expect(cubit.isMemberRunning('m-lead'), isTrue);
        expect(cubit.isMemberRunning('m-dev'), isTrue);
        expect(cubit.state.selectedMemberId, 'm-lead');
        expect(fakeSessions, hasLength(2));
        expect(
          fakeSessions.map((shell) => shell.connectedSessionTeams.single),
          everyElement('team-a-1'),
        );
      },
    );

    test(
      'closeTabsForProject counts and terminates a project\'s open tabs',
      () async {
        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_close_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        final projectA = await repo.createProject('/a', teamId: 'team-a');
        final projectB = await repo.createProject('/b', teamId: 'team-a');
        final sessionA = await repo.createSession(
          projectA.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final sessionB = await repo.createSession(
          projectB.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        addTearDown(cubit.close);

        await cubit.openSessionTab(sessionA, team: team, member: team.members.first, repo: repo);
        await cubit.openSessionTab(sessionB, team: team, member: team.members.first, repo: repo);
        await postFrame.flush();

        expect(cubit.state.tabs.length, 2);
        expect(cubit.openTabCountForProject(projectA.projectId), 1);
        expect(cubit.openTabCountForProject(projectB.projectId), 1);
        expect(cubit.openTabCountForProject('no-such-project'), 0);

        cubit.closeTabsForProject(projectA.projectId);

        expect(cubit.state.tabs.length, 1);
        expect(cubit.openTabCountForProject(projectA.projectId), 0);
        expect(cubit.openTabCountForProject(projectB.projectId), 1);
      },
    );

    test(
      'connectSession auto-launch does not reconnect queued member shells',
      () async {
        final scheduled = <void Function()>[];
        final fakeSessions = <_FakeTerminalSession>[];
        final cubit = ChatCubit(
          executableResolver: () => 'true',
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
        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );

        await cubit.connectSession(team);
        await drainPostFrameQueue(scheduled);

        final connectedMembers = fakeSessions
            .expand((session) => session.connectedMembers)
            .toList();
        expect(connectedMembers.where((id) => id == 'm-lead'), hasLength(1));
        expect(connectedMembers.where((id) => id == 'm-dev'), hasLength(1));
        expect(cubit.isMemberRunning('m-lead'), isTrue);
        expect(cubit.isMemberRunning('m-dev'), isTrue);
      },
    );

    test(
      'mixed openSessionTab seeds member shell with member cli executable',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamConfig(
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
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_mixed_cli_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        final project = await repo.createProject('/tmp', teamId: '');
        final session = await repo.createSession(
          project.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'flashskyai',
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
        addTearDown(cubit.close);

        await cubit.openSessionTab(
          session,
          team: team,
          member: team.members.first,
          repo: repo,
          connectImmediately: false,
        );
        await postFrame.flush();

        expect(fakeSessions, hasLength(1));
        expect(fakeSessions.single.executable, 'claude');
      },
    );

    test(
      'mixed openSessionTab auto-connects team-lead',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamConfig(
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
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        final project = await repo.createProject('/tmp', teamId: '');
        final session = await repo.createSession(
          project.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
            final fake = _FakeTerminalSession(executable: executable);
            fakeSessions.add(fake);
            return fake;
          },
          postFrameScheduler: postFrame.scheduler,
        );
        addTearDown(cubit.close);

        await cubit.openSessionTab(
          session,
          team: team,
          member: team.members.first,
          repo: repo,
        );
        await postFrame.flush();

        expect(cubit.state.tabs.length, 1);
        expect(cubit.isMemberRunning('team-lead'), isTrue);
        expect(
          fakeSessions.expand((s) => s.connectedMembers),
          contains('team-lead'),
        );
        expect(cubit.isMemberRunning('m-dev'), isFalse);
      },
    );

    test(
      'mixed openSessionTab does not connect non-lead until user connect',
      () async {
        final fakeSessions = <_FakeTerminalSession>[];
        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          teamMode: TeamMode.mixed,
          members: [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_mixed_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        final project = await repo.createProject('/tmp', teamId: '');
        final session = await repo.createSession(
          project.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) {
            final fake = _FakeTerminalSession(executable: executable);
            fakeSessions.add(fake);
            return fake;
          },
          postFrameScheduler: postFrame.scheduler,
        );
        addTearDown(cubit.close);

        await cubit.openSessionTab(
          session,
          team: team,
          member: team.members[1],
          repo: repo,
          connectImmediately: true,
        );
        await postFrame.flush();

        expect(cubit.state.tabs.length, 1);
        expect(cubit.isMemberRunning('team-lead'), isFalse);
        expect(cubit.isMemberRunning('m-dev'), isFalse);
        expect(fakeSessions.expand((s) => s.connectedMembers), isEmpty);

        await cubit.connectSession(team, repo: repo);
        await postFrame.flush();

        expect(cubit.isMemberRunning('m-dev'), isTrue);
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
        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final project = await repo.createProject('/tmp', teamId: '');
        final session = await repo.createSession(
          project.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );
        final cubit = ChatCubit(
          executableResolver: () => 'true',
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

        await cubit.openSessionTab(
          session,
          team: team,
          member: team.members.first,
          repo: repo,
        );
        await drainPostFrameQueue(scheduled);
        scheduled.clear();

        await cubit.openMemberTab(team, team.members[1]);
        expect(scheduled, hasLength(1));

        await cubit.openMemberTab(team, team.members[1]);
        expect(scheduled, hasLength(1));

        await drainPostFrameQueue(scheduled);

        expect(
          fakeSessions.expand((s) => s.connectedMembers).where((id) => id == 'm-dev'),
          hasLength(1),
        );
      },
    );

    test(
      'openMemberTab reuses existing team project when workspace cwd is set',
      () async {
        const team = TeamConfig(
          id: 'team-default',
          name: 'Default Team',
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_materialize_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        const workspacePath = '/tmp/default-team-workspace';
        final project = await repo.createProject(
          workspacePath,
          teamId: team.id,
          display: 'Default Team',
        );
        await repo.createSession(
          project.projectId,
          sessionTeam: team.id,
          rosterMembers: team.members,
        );

        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          sessionRepository: repo,
          postFrameScheduler: postFrame.scheduler,
        );
        addTearDown(cubit.close);

        await cubit.loadProjectData(repo);
        expect(cubit.state.projects, hasLength(1));

        await cubit.openMemberTab(
          team,
          team.members.first,
          repo: repo,
          workspaceCwd: workspacePath,
        );
        await postFrame.flush();

        expect(cubit.state.projects, hasLength(1));
        expect(cubit.state.projects.single.primaryPath, workspacePath);
        expect(cubit.state.tabs, hasLength(1));
      },
    );
  });
}
