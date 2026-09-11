import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/presence_event_bridge.dart';
import 'package:teampilot/services/team/member_presence_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

const _team = TeamProfile(
  id: 'team-a',
  name: 'A',
  members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
);

const _seat = PresenceSeatKey(sessionId: 's-1', memberId: 'm-lead');

/// Mirrors the existing cubit-test shell, plus a bound presence seat so the
/// event path (projection lookup / bridge report) has an identity to key on.
class _FakePresenceSession extends TerminalSession {
  _FakePresenceSession({required super.executable, this.seat})
    : super(fs: InMemoryFilesystem());

  final PresenceSeatKey? seat;

  @override
  PresenceSeatKey? get presenceSeat => seat;
}

/// Returns a scripted snapshot, so a test can flip connection/availability
/// between ticks without touching PTY state.
class _StubPresenceService extends MemberPresenceService {
  _StubPresenceService(this.result) : super(storage: fakeHomeStorage());

  Map<String, MemberPresence> result;
  var computeCalls = 0;

  @override
  Future<Map<String, MemberPresence>> compute({
    required CliTool teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
    PresenceSessionContext? session,
  }) async {
    computeCalls++;
    return result;
  }
}

/// Records published events and (optionally) feeds them back into a projection,
/// standing in for the dispatcher hop in production wiring.
class _RecordingSink implements AgentPresenceSink {
  _RecordingSink({this.projection});

  final AgentPresenceProjection? projection;
  final events = <AgentPresenceEvent>[];

  @override
  void publish(AgentPresenceEvent event) {
    events.add(event);
    projection?.handle(event);
  }
}

PresenceTarget _target(TerminalSession shell) => PresenceTarget(
  cliTeamName: 'team-a-1',
  memberToolConfigDir: '/tmp/cfg',
  memberShells: {'m-lead': shell},
);

const _connectedWorking = MemberPresence(
  connection: MemberConnection.connected,
  availability: MemberAvailability.working,
);
const _connectedIdle = MemberPresence(
  connection: MemberConnection.connected,
  availability: MemberAvailability.idle,
);
const _disconnected = MemberPresence(connection: MemberConnection.offline);

void _pumpFrame() {
  SchedulerBinding.instance.handleBeginFrame(Duration.zero);
  SchedulerBinding.instance.handleDrawFrame();
}

/// Drives one poll: run the restart post-frame, let compute settle, then run
/// the emit post-frame.
void _settlePoll(FakeAsync async) {
  _pumpFrame();
  async.elapse(const Duration(milliseconds: 50));
  async.flushMicrotasks();
  _pumpFrame();
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('MemberPresenceCubit event consumption', () {
    test('projection changes notify the listener', () async {
      final projection = AgentPresenceProjection();
      var refreshes = 0;
      final cubit = MemberPresenceCubit(
        storage: fakeHomeStorage(),
        presenceProjection: projection,
        onProjectionChanged: () => refreshes++,
      );
      addTearDown(cubit.close);

      projection.handle(
        AgentPresenceEvent(
          seat: const PresenceSeatKey(sessionId: 's', memberId: 'm'),
          eventKind: AgentPresenceKind.working,
          timestamp: DateTime(2026, 9, 11),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 1);
    });

    test('emitted availability reads the projection when wired', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        // compute() still says idle — the projection value must win.
        final service = _StubPresenceService({'m-lead': _connectedIdle});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        projection.handle(
          AgentPresenceEvent(
            seat: _seat,
            eventKind: AgentPresenceKind.working,
            timestamp: DateTime(2026, 9, 11),
          ),
        );

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);

        expect(
          cubit.state.presence['m-lead']?.connection,
          MemberConnection.connected,
        );
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.working,
        );
      });
    });

    test('connection still comes from the poll when the projection has a value', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final service = _StubPresenceService({
          'm-lead': const MemberPresence(connection: MemberConnection.connecting),
        });
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        projection.handle(
          AgentPresenceEvent(
            seat: _seat,
            eventKind: AgentPresenceKind.working,
            timestamp: DateTime(2026, 9, 11),
          ),
        );

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);

        final presence = cubit.state.presence['m-lead'];
        expect(presence?.connection, MemberConnection.connecting);
        expect(
          presence?.availability,
          isNull,
          reason: 'availability is only meaningful once connected',
        );
      });
    });

    test('no projection wired keeps the compute-derived availability', () {
      fakeAsync((async) {
        final service = _StubPresenceService({'m-lead': _connectedIdle});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);

        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.idle,
        );
        expect(
          shell.onPresenceInputsChanged,
          isNull,
          reason: 'no events path wired -> no push trigger attached',
        );
      });
    });

    test('reports availability to the bridge and clears it on disconnect', () {
      fakeAsync((async) {
        final sink = _RecordingSink();
        final bridge = PresenceEventBridge(sink: sink);
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceBridge: bridge,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);
        expect(
          sink.events.map((e) => e.eventKind).toList(),
          [AgentPresenceKind.working],
        );

        // Disconnect: reports null (no publish) but clears the bridge baseline.
        service.result = {'m-lead': _disconnected};
        cubit.tickFromIdleWatch();
        _settlePoll(async);
        expect(sink.events.length, 1, reason: 'null report publishes nothing');

        // Reconnect at the same value republishes, proving the baseline cleared.
        service.result = {'m-lead': _connectedWorking};
        cubit.tickFromIdleWatch();
        _settlePoll(async);
        expect(
          sink.events.map((e) => e.eventKind).toList(),
          [AgentPresenceKind.working, AgentPresenceKind.working],
        );
      });
    });

    test('compute changes republish through the bridge into the projection', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final sink = _RecordingSink(projection: projection);
        final bridge = PresenceEventBridge(sink: sink);
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
          presenceBridge: bridge,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);
        expect(projection.availabilityFor(_seat), AgentPresenceKind.working);

        service.result = {'m-lead': _connectedIdle};
        cubit.tickFromIdleWatch();
        _settlePoll(async);

        expect(
          projection.availabilityFor(_seat),
          AgentPresenceKind.idle,
          reason: 'the poll keeps the publish edge feeding the projection',
        );
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.idle,
        );
      });
    });

    test('reconnect at a different value converges to the fresh availability', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final sink = _RecordingSink(projection: projection);
        final bridge = PresenceEventBridge(sink: sink);
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
          presenceBridge: bridge,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);
        expect(projection.availabilityFor(_seat), AgentPresenceKind.working);

        // Disconnect: reports null (clears the bridge baseline) but the
        // projection keeps the last kind.
        service.result = {'m-lead': _disconnected};
        cubit.tickFromIdleWatch();
        _settlePoll(async);
        expect(projection.availabilityFor(_seat), AgentPresenceKind.working);

        // Reconnect into a fresh boot: the poll keeps feeding the bridge, so
        // the projection converges rather than freezing on the stale value.
        service.result = {
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            availability: MemberAvailability.booting,
          ),
        };
        cubit.tickFromIdleWatch();
        _settlePoll(async);

        expect(projection.availabilityFor(_seat), AgentPresenceKind.booting);
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.booting,
        );
      });
    });

    test('reconnect at the same value: no re-broadcast, UI still correct', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final sink = _RecordingSink(projection: projection);
        final bridge = PresenceEventBridge(sink: sink);
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        var refreshes = 0;
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
          presenceBridge: bridge,
          onProjectionChanged: () => refreshes++,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);
        expect(projection.availabilityFor(_seat), AgentPresenceKind.working);
        final refreshesAfterInitial = refreshes;

        service.result = {'m-lead': _disconnected};
        cubit.tickFromIdleWatch();
        _settlePoll(async);

        service.result = {'m-lead': _connectedWorking};
        cubit.tickFromIdleWatch();
        _settlePoll(async);

        // The bridge republishes (baseline was cleared) but the projection
        // absorbs the equal value, so `changes` never fires (Task-4 note).
        expect(sink.events.length, 2);
        expect(
          refreshes,
          refreshesAfterInitial,
          reason: 'projection dedupes the equal reconnect value',
        );
        // The UI is nonetheless correct: the projected value equals the fresh
        // one, and the 1s poll reads availabilityFor every tick.
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.working,
        );
        expect(
          cubit.state.presence['m-lead']?.connection,
          MemberConnection.connected,
        );
      });
    });

    test('attaches the push trigger and clears it when the target is replaced', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final service = _StubPresenceService({'m-lead': _connectedIdle});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);

        expect(shell.onPresenceInputsChanged, isNotNull);
        final callsBefore = service.computeCalls;
        shell.onPresenceInputsChanged!();
        async.flushMicrotasks();
        expect(service.computeCalls, greaterThan(callsBefore));

        cubit.updateTarget(null);
        expect(shell.onPresenceInputsChanged, isNull);
      });
    });

    test('stopPresencePolling clears the push trigger', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: _StubPresenceService({'m-lead': _connectedIdle}),
          presenceProjection: projection,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);
        expect(shell.onPresenceInputsChanged, isNotNull);

        cubit.stopPresencePolling();
        expect(shell.onPresenceInputsChanged, isNull);
      });
    });

    test('close cancels the subscription, disposes the bridge, drops seats', () {
      fakeAsync((async) {
        final projection = AgentPresenceProjection();
        final sink = _RecordingSink(projection: projection);
        final bridge = PresenceEventBridge(sink: sink);
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        var projectionRefreshes = 0;
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: projection,
          presenceBridge: bridge,
          onProjectionChanged: () => projectionRefreshes++,
        );
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settlePoll(async);
        expect(projection.availabilityFor(_seat), AgentPresenceKind.working);
        expect(projectionRefreshes, greaterThan(0));

        cubit.close();
        async.flushMicrotasks();

        expect(shell.onPresenceInputsChanged, isNull);
        expect(
          projection.availabilityFor(_seat),
          isNull,
          reason: 'closed cubit drops its seats from the projection',
        );
        final publishedBefore = sink.events.length;
        bridge.reportAvailability(_seat, AgentPresenceKind.idle);
        expect(
          sink.events.length,
          publishedBefore,
          reason: 'the bridge is disposed at close',
        );
        final refreshesBefore = projectionRefreshes;
        projection.handle(
          AgentPresenceEvent(
            seat: _seat,
            eventKind: AgentPresenceKind.booting,
            timestamp: DateTime(2026, 9, 11),
          ),
        );
        async.flushMicrotasks();
        expect(
          projectionRefreshes,
          refreshesBefore,
          reason: 'close cancels the projection subscription',
        );
      });
    });
  });
}
