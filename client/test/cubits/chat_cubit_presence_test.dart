import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/team/member_presence_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';

class _FakeTerminalSession extends TerminalSession {
  _FakeTerminalSession({required super.executable});

  var _running = false;

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

class _DelayedPresenceService extends MemberPresenceService {
  _DelayedPresenceService(
    this.result, {
    this.delay = const Duration(milliseconds: 80),
  });

  final Map<String, MemberPresence> result;
  final Duration delay;
  var computeCalls = 0;

  @override
  Future<Map<String, MemberPresence>> compute({
    required TeamCli teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
  }) async {
    computeCalls++;
    await Future<void>.delayed(delay);
    return result;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit presence polling', () {
    test('does not poll until UI is attached', () async {
      final service = _DelayedPresenceService(const {});
      final harness = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'true',
        postFrameScheduler: harness.scheduler,
        memberPresenceService: service,
      );
      addTearDown(cubit.close);

      const team = TeamConfig(
        id: 'team-a',
        name: 'A',
        members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
      );
      cubit.syncPresenceTeam(team);
      await harness.flush();
      expect(service.computeCalls, 0);
    });

    test('detach invalidates in-flight tick', () {
      fakeAsync((async) {
        final service = _DelayedPresenceService({
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            workload: MemberWorkload.working,
          ),
        });
        final harness = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          postFrameScheduler: harness.scheduler,
          memberPresenceService: service,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
        );

        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        unawaited(cubit.connectSession(team));
        async.flushMicrotasks();
        unawaited(harness.flush());
        async.flushMicrotasks();

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(team);
        async.flushMicrotasks();
        unawaited(harness.flush());
        async.flushMicrotasks();

        cubit.detachPresenceUi();
        expect(cubit.state.memberPresence, isEmpty);

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(cubit.state.memberPresence, isEmpty);

        cubit.close();
      });
    });

    test('selectTab to tab without shells stops polling', () async {
      fakeAsync((async) {
        final service = _DelayedPresenceService(const {});
        final harness = PostFrameTestHarness();
        final tmp = Directory.systemTemp.createTempSync('presence_tabs_');
        final repo = SessionRepository(rootDir: tmp.path);
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          postFrameScheduler: harness.scheduler,
          memberPresenceService: service,
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
        );

        const team = TeamConfig(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        unawaited(cubit.connectSession(team));
        async.flushMicrotasks();
        unawaited(harness.flush());
        async.flushMicrotasks();

        unawaited(
          repo.createProject('/tmp').then((project) async {
            final localSession = await repo.createSession(project.projectId);
            await cubit.openSessionTab(localSession, connectImmediately: false);
            async.flushMicrotasks();
            unawaited(harness.flush());
            async.flushMicrotasks();

            cubit.attachPresenceUi();
            cubit.syncPresenceTeam(team);
            async.flushMicrotasks();
            unawaited(harness.flush());
            async.flushMicrotasks();

            expect(service.computeCalls, greaterThan(0));
            final callsWithTeamTab = service.computeCalls;

            cubit.selectTab(1);
            async.flushMicrotasks();
            unawaited(harness.flush());
            async.flushMicrotasks();

            async.elapse(const Duration(seconds: 2));
            async.flushMicrotasks();
            expect(service.computeCalls, callsWithTeamTab);

            await cubit.close();
            if (tmp.existsSync()) {
              tmp.deleteSync(recursive: true);
            }
          }),
        );
        async.elapse(const Duration(seconds: 5));
      });
    });
  });
}
