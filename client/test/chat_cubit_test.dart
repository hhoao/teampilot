import 'dart:io';

import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

Future<void> _deleteTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      return;
    } on PathAccessException {
      await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
    }
  }
}

class _FakeTerminalSession extends TerminalSession {
  _FakeTerminalSession({required super.executable});

  var _running = false;
  final connectedMembers = <String>[];
  final connectedSessionTeams = <String?>[];

  @override
  bool get isRunning => _running;

  @override
  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    TeamConfig? team,
    TeamMemberConfig? member,
    String? sessionTeam,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
  }) {
    if (member != null) {
      connectedMembers.add(member.id);
    }
    connectedSessionTeams.add(sessionTeam);
    _running = true;
    onProcessStarted?.call();
  }

  @override
  void disconnect() {
    _running = false;
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
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
          AppProject(
            projectId: pB,
            primaryPath: '/b',
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
      await cubit.close();
      await _deleteTempDir(tmp);
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
      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.selectedMemberId, 'm-lead');
    });

    test('uses team cli executable for member shell', () async {
      final executables = <String>[];
      final cubit = ChatCubit(
        executableResolver: () => 'flashskyai',
        cliExecutableResolver: (cli) =>
            cli == TeamCli.claude ? '/opt/bin/claude' : 'flashskyai',
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
        cli: TeamCli.claude,
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
        const session = AppSession(
          sessionId: 'session-1',
          projectId: 'project-1',
          primaryPath: '/tmp',
          createdAt: 1,
        );
        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [
            TeamMemberConfig(id: 'm-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'm-dev', name: 'developer'),
          ],
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
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
        );
        await postFrame.flush();

        expect(cubit.state.tabs.length, 1);
        expect(cubit.isMemberRunning('m-lead'), isTrue);
        expect(cubit.isMemberRunning('m-dev'), isTrue);
        expect(cubit.state.selectedMemberId, 'm-lead');
        expect(fakeSessions, hasLength(2));
        expect(
          fakeSessions.map((session) => session.connectedSessionTeams.single),
          everyElement(fakeSessions.first.connectedSessionTeams.single),
        );
        expect(fakeSessions.first.connectedSessionTeams.single, isNotEmpty);
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
  });
}
