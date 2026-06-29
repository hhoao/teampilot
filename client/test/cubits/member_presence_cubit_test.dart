import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/team/member_presence_service.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
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
  void disconnect() {
    _running = false;
  }

  @override
  void dispose() {
    _running = false;
  }
}

class _DelayedPresenceService extends MemberPresenceService {
  _DelayedPresenceService(this.result);

  static const _delay = Duration(milliseconds: 80);

  final Map<String, MemberPresence> result;
  var computeCalls = 0;

  @override
  Future<Map<String, MemberPresence>> compute({
    required CliTool teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
    MemberWorkload Function(String memberId)? workloadResolver,
  }) async {
    computeCalls++;
    await Future<void>.delayed(_delay);
    return result;
  }
}

class _TrackingPresenceService extends MemberPresenceService {
  var computeCalls = 0;
  List<TeamMemberConfig>? lastMembers;

  @override
  Future<Map<String, MemberPresence>> compute({
    required CliTool teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
    MemberWorkload Function(String memberId)? workloadResolver,
  }) async {
    computeCalls++;
    lastMembers = members;
    return {
      for (final m in members)
        m.id: const MemberPresence(
          connection: MemberConnection.connected,
          workload: MemberWorkload.idle,
        ),
    };
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('MemberPresenceCubit polling', () {
    test('does not poll until UI is attached', () async {
      final service = _DelayedPresenceService(const {});
      final harness = PostFrameTestHarness();
      final cubit = MemberPresenceCubit(memberPresenceService: service);
      addTearDown(cubit.close);

      const team = TeamProfile(
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
        final presenceCubit = MemberPresenceCubit(
          memberPresenceService: service,
        );
        final chatCubit = ChatCubit(
          executableResolver: () => 'true',
          postFrameScheduler: harness.scheduler,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
        );
        chatCubit.bindPresenceCubit(presenceCubit);

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        unawaited(chatCubit.connectWorkspaceSession(TeamSessionConnect(team)));
        async.flushMicrotasks();
        unawaited(harness.flush());
        async.flushMicrotasks();

        presenceCubit.attachPresenceUi();
        presenceCubit.syncPresenceTeam(team);
        async.flushMicrotasks();
        unawaited(harness.flush());
        async.flushMicrotasks();

        presenceCubit.detachPresenceUi();
        expect(presenceCubit.state.presence, isEmpty);

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(presenceCubit.state.presence, isEmpty);

        unawaited(chatCubit.close());
        unawaited(presenceCubit.close());
      });
    });

    // ── workspace switch: overlapping panel attach/detach must not drop UI ──

    test(
        'survives workspace switch: new panel attaches before old panel detaches',
        () {
      fakeAsync((async) {
        final service = _DelayedPresenceService({
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            workload: MemberWorkload.working,
          ),
        });
        final cubit = MemberPresenceCubit(memberPresenceService: service);
        addTearDown(() async {
          await cubit.close();
        });

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        final shell = _FakeTerminalSession(executable: 'test');
        PresenceTarget target() => PresenceTarget(
              cliTeamName: 'team-a-1',
              memberToolConfigDir: '/tmp/cfg',
              memberShells: {'m-lead': shell},
            );

        void pumpFrame() {
          SchedulerBinding.instance.handleBeginFrame(Duration.zero);
          SchedulerBinding.instance.handleDrawFrame();
        }

        // Two RightToolsPanel instances (one per workspace page) share the single
        // global cubit. Each panel owns its attach/detach.
        final panelA = Object();
        final panelB = Object();

        // Workspace A page mounted → polling starts, presence populated.
        cubit.attachPresenceUi(panelA);
        cubit.syncPresenceTeam(team);
        cubit.updateTarget(target());
        pumpFrame();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        pumpFrame();
        expect(
          cubit.state.presence['m-lead']?.connection,
          MemberConnection.connected,
        );
        final callsAfterA = service.computeCalls;

        // Switch to workspace B. Flutter inflates workspace B's panel (attach)
        // during the build, then finalizeTree disposes workspace A's panel
        // (detach) AFTER. The cubit must stay attached throughout.
        cubit.attachPresenceUi(panelB);
        cubit.updateTarget(target());
        cubit.detachPresenceUi(panelA);

        // Presence must NOT be cleared by the late detach.
        expect(
          cubit.state.presence,
          isNotEmpty,
          reason: 'workspace switch must not drop member presence to offline',
        );

        // Polling must keep running for the still-mounted workspace B panel.
        pumpFrame();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        pumpFrame();
        expect(
          service.computeCalls,
          greaterThan(callsAfterA),
          reason: 'polling must keep running after a workspace switch',
        );
        expect(
          cubit.state.presence['m-lead']?.connection,
          MemberConnection.connected,
        );
      });
    });

    // ── hysteresis: keep last-known presence on transient ineligibility ──

    test('keeps presence when updateTarget(null), resumes when target restored',
        () {
      fakeAsync((async) {
        final service = _DelayedPresenceService({
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            workload: MemberWorkload.working,
          ),
        });
        final cubit = MemberPresenceCubit(memberPresenceService: service);
        addTearDown(() async {
          await cubit.close();
        });

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(team);

        final shell = _FakeTerminalSession(executable: 'test');
        cubit.updateTarget(PresenceTarget(
          cliTeamName: 'team-a-1',
          memberToolConfigDir: '/tmp/cfg',
          memberShells: {'m-lead': shell},
        ));

        // Manually run a frame to process post-frame callbacks from
        // _schedulePresencePollingRestart. SchedulerBinding won't auto-fire
        // frames in fakeAsync.
        void pumpFrame() {
          SchedulerBinding.instance.handleBeginFrame(Duration.zero);
          SchedulerBinding.instance.handleDrawFrame();
        }

        pumpFrame();
        // Advance past the 80ms service delay so compute completes.
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        // Process post-frame callback that _emitMemberPresence scheduled.
        pumpFrame();

        expect(service.computeCalls, greaterThan(0));
        expect(
          cubit.state.presence['m-lead']?.connection,
          MemberConnection.connected,
        );
        final callsAfterFirstPoll = service.computeCalls;

        // Transient ineligibility: null target should NOT clear presence.
        cubit.updateTarget(null);
        pumpFrame();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(service.computeCalls, callsAfterFirstPoll); // no new polls
        expect(cubit.state.presence, isNotEmpty); // presence KEPT (not cleared)

        // Restore target → polling resumes.
        cubit.updateTarget(PresenceTarget(
          cliTeamName: 'team-a-1',
          memberToolConfigDir: '/tmp/cfg',
          memberShells: {'m-lead': shell},
        ));
        pumpFrame();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        pumpFrame();

        expect(service.computeCalls, greaterThan(callsAfterFirstPoll));
        expect(cubit.state.presence, isNotEmpty);
      });
    });

    test('stopPresencePolling clears presence', () {
      fakeAsync((async) {
        final service = _DelayedPresenceService({
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            workload: MemberWorkload.working,
          ),
        });
        final cubit = MemberPresenceCubit(memberPresenceService: service);
        addTearDown(() async {
          await cubit.close();
        });

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(team);

        final shell = _FakeTerminalSession(executable: 'test');
        cubit.updateTarget(PresenceTarget(
          cliTeamName: 'team-a-1',
          memberToolConfigDir: '/tmp/cfg',
          memberShells: {'m-lead': shell},
        ));

        // stopPresencePolling synchronously clears state.
        cubit.stopPresencePolling();
        expect(cubit.state.presence, isEmpty);
      });
    });

    test('detachPresenceUi clears presence', () {
      fakeAsync((async) {
        final service = _DelayedPresenceService({
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            workload: MemberWorkload.working,
          ),
        });
        final cubit = MemberPresenceCubit(memberPresenceService: service);
        addTearDown(() async {
          await cubit.close();
        });

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(team);

        final shell = _FakeTerminalSession(executable: 'test');
        cubit.updateTarget(PresenceTarget(
          cliTeamName: 'team-a-1',
          memberToolConfigDir: '/tmp/cfg',
          memberShells: {'m-lead': shell},
        ));

        // detachPresenceUi synchronously clears state.
        cubit.detachPresenceUi();
        expect(cubit.state.presence, isEmpty);
      });
    });

    test('selectTab to tab without shells stops polling', () async {
      fakeAsync((async) {
        final service = _DelayedPresenceService(const {});
        final harness = PostFrameTestHarness();
        final tmp = Directory.systemTemp.createTempSync('presence_tabs_');
        final repo = SessionRepository(rootDir: tmp.path);
        final presenceCubit = MemberPresenceCubit(
          memberPresenceService: service,
        );
        final chatCubit = ChatCubit(
          executableResolver: () => 'true',
          postFrameScheduler: harness.scheduler,
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
        );
        chatCubit.bindPresenceCubit(presenceCubit);

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );

        unawaited(chatCubit.connectWorkspaceSession(TeamSessionConnect(team)));
        async.flushMicrotasks();
        unawaited(harness.flush());
        async.flushMicrotasks();

        unawaited(
          repo.createWorkspace([WorkspaceFolder(path: '/tmp')]).then((workspace) async {
            final localSession = await repo.createSession(workspace.workspaceId);
            await chatCubit.requestOpenSession(
        SessionOpenRequest(
          session: localSession, connectImmediately: false,
        ),
      );
            async.flushMicrotasks();
            unawaited(harness.flush());
            async.flushMicrotasks();

            presenceCubit.attachPresenceUi();
            presenceCubit.syncPresenceTeam(team);
            async.flushMicrotasks();
            unawaited(harness.flush());
            async.flushMicrotasks();

            expect(service.computeCalls, greaterThan(0));
            final callsWithTeamTab = service.computeCalls;

            chatCubit.selectTab(1);
            async.flushMicrotasks();
            unawaited(harness.flush());
            async.flushMicrotasks();

            async.elapse(const Duration(seconds: 2));
            async.flushMicrotasks();
            expect(service.computeCalls, callsWithTeamTab);

            await chatCubit.close();
            await presenceCubit.close();
            if (tmp.existsSync()) {
              tmp.deleteSync(recursive: true);
            }
          }),
        );
        async.elapse(const Duration(seconds: 5));
      });
    });

    test('reuses runtime roster and presence instances while idle', () {
      fakeAsync((async) {
        final service = _TrackingPresenceService();
        final cubit = MemberPresenceCubit(memberPresenceService: service);
        addTearDown(() async {
          await cubit.close();
        });

        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final shell = _FakeTerminalSession(executable: 'test');

        void pumpFrame() {
          SchedulerBinding.instance.handleBeginFrame(Duration.zero);
          SchedulerBinding.instance.handleDrawFrame();
        }

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(team);
        cubit.updateTarget(PresenceTarget(
          cliTeamName: 'team-a-1',
          memberToolConfigDir: '/tmp/cfg',
          memberShells: {'m-lead': shell},
        ));

        pumpFrame();
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();
        pumpFrame();

        final firstMembers = service.lastMembers;
        final firstPresence = cubit.state.presence['m-lead'];
        expect(firstMembers, isNotNull);
        expect(firstPresence, isNotNull);

        pumpFrame();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        pumpFrame();

        expect(service.computeCalls, greaterThan(1));
        expect(identical(service.lastMembers, firstMembers), isTrue);
        expect(identical(cubit.state.presence['m-lead'], firstPresence), isTrue);
      });
    });
  });
}
