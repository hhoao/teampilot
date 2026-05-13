import 'package:flashskyai_client/cubits/chat_cubit.dart';
import 'package:flashskyai_client/models/app_project.dart';
import 'package:flashskyai_client/models/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

String _executable() => 'flashskyai';

void main() {
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
      expect(
        cubit.state.visibleProjects.map((e) => e.projectId).toSet(),
        {'p-a', 'p-b'},
      );
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
}
