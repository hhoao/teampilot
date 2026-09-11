import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
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

/// Records publishes synchronously, with an optional synchronous feed into a
/// projection.
///
/// This models only the *enqueue* half of the production path (bridge →
/// `sink.publish` is synchronous) and deliberately skips the dispatcher's async
/// delivery hop, so it is only used by tests that do NOT assert convergence
/// through the dispatcher. Convergence tests use [_wiredEventsPath].
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

/// Production-shaped presence wiring: a real [AsyncDispatcher] delivers bridge
/// publishes to the projection on a later event-loop turn (the single consume
/// loop), and [AgentPresenceProjection.changes] then triggers the cubit's
/// recompute. The hop is why availability convergence is settled in a loop
/// rather than asserted on the same tick.
///
/// [AsyncDispatcher.handledCounts] counts every *delivered* event (including
/// ones the projection absorbs) — the production observable for "published".
({
  AsyncDispatcher dispatcher,
  AgentPresenceProjection projection,
  PresenceEventBridge bridge,
})
_wiredEventsPath() {
  final dispatcher = AsyncDispatcher()..start();
  final projection = AgentPresenceProjection();
  dispatcher.registerFamily<AgentPresenceKind>(
    AgentPresenceKind.booting.runtimeType,
    projection,
  );
  final bridge = PresenceEventBridge(
    sink: DispatcherAgentPresenceSink(dispatcher),
  );
  return (dispatcher: dispatcher, projection: projection, bridge: bridge);
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

/// Runs poll→emit cycles until [ok] holds, letting each bridge publish land on
/// the dispatcher's consume loop and the resulting `changes` recompute settle
/// before the next poll. Bounded, so a value stuck one hop behind fails the
/// following assertion instead of hanging the test.
void _settleUntil(FakeAsync async, bool Function() ok, {int maxPolls = 8}) {
  for (var i = 0; i < maxPolls && !ok(); i++) {
    _settlePoll(async);
  }
}

/// Stops the dispatcher (draining anything queued) before the fake zone ends,
/// so no fake-zone microtask is left pending after the test body.
void _stopDispatcher(FakeAsync async, AsyncDispatcher dispatcher) {
  dispatcher.stop();
  async.flushMicrotasks();
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
        // Synchronous read-path case: the projection is seeded directly (as if
        // a prior event had already been delivered) and the cubit's apply-step
        // reads it on the next poll — no dispatcher hop is exercised here.
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
        // Synchronous read-path case (see the previous test): the projection is
        // seeded directly; connection must stay poll-derived regardless.
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

        // Disconnect: reports null, bridge publishes cleared and clears baseline.
        service.result = {'m-lead': _disconnected};
        cubit.tickFromIdleWatch();
        _settlePoll(async);
        expect(
          sink.events.map((e) => e.eventKind).toList(),
          [AgentPresenceKind.working, AgentPresenceKind.cleared],
          reason: 'disconnect publishes cleared so transport can fan it out',
        );

        // Reconnect at the same value republishes, proving the baseline cleared.
        service.result = {'m-lead': _connectedWorking};
        cubit.tickFromIdleWatch();
        _settlePoll(async);
        expect(
          sink.events.map((e) => e.eventKind).toList(),
          [
            AgentPresenceKind.working,
            AgentPresenceKind.cleared,
            AgentPresenceKind.working,
          ],
        );
      });
    });

    test('compute changes republish through the bridge into the projection', () {
      fakeAsync((async) {
        final wired = _wiredEventsPath();
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: wired.projection,
          presenceBridge: wired.bridge,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settleUntil(
          async,
          () => wired.projection.availabilityFor(_seat) ==
              AgentPresenceKind.working,
        );

        service.result = {'m-lead': _connectedIdle};
        cubit.tickFromIdleWatch();
        // Availability lands one dispatcher hop late: the detecting tick still
        // reads the pre-change projected value, then `changes` recomputes.
        _settleUntil(
          async,
          () => wired.projection.availabilityFor(_seat) ==
                  AgentPresenceKind.idle &&
              cubit.state.presence['m-lead']?.availability ==
                  MemberAvailability.idle,
        );

        expect(
          wired.projection.availabilityFor(_seat),
          AgentPresenceKind.idle,
          reason: 'the poll keeps the publish edge feeding the projection',
        );
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.idle,
        );
        _stopDispatcher(async, wired.dispatcher);
      });
    });

    test('reconnect at a different value converges to the fresh availability', () {
      fakeAsync((async) {
        final wired = _wiredEventsPath();
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: wired.projection,
          presenceBridge: wired.bridge,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settleUntil(
          async,
          () => wired.projection.availabilityFor(_seat) ==
              AgentPresenceKind.working,
        );

        // Disconnect: reports null, bridge publishes cleared, projection
        // tombstones the seat.
        service.result = {'m-lead': _disconnected};
        cubit.tickFromIdleWatch();
        _settleUntil(
          async,
          () => cubit.state.presence['m-lead']?.connection ==
                  MemberConnection.offline &&
              wired.projection.availabilityFor(_seat) == null,
        );
        expect(wired.projection.availabilityFor(_seat), isNull);

        // Reconnect into a fresh boot: the poll keeps feeding the bridge, so
        // the projection converges to the new availability.
        service.result = {
          'm-lead': const MemberPresence(
            connection: MemberConnection.connected,
            availability: MemberAvailability.booting,
          ),
        };
        cubit.tickFromIdleWatch();
        _settleUntil(
          async,
          () => wired.projection.availabilityFor(_seat) ==
                  AgentPresenceKind.booting &&
              cubit.state.presence['m-lead']?.availability ==
                  MemberAvailability.booting,
        );

        expect(
          wired.projection.availabilityFor(_seat),
          AgentPresenceKind.booting,
        );
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.booting,
        );
        _stopDispatcher(async, wired.dispatcher);
      });
    });

    test('reconnect at the same value republishes after cleared', () {
      fakeAsync((async) {
        final wired = _wiredEventsPath();
        final service = _StubPresenceService({'m-lead': _connectedWorking});
        var refreshes = 0;
        final cubit = MemberPresenceCubit(
          storage: fakeHomeStorage(),
          memberPresenceService: service,
          presenceProjection: wired.projection,
          presenceBridge: wired.bridge,
          onProjectionChanged: () => refreshes++,
        );
        addTearDown(cubit.close);
        final shell = _FakePresenceSession(executable: 't', seat: _seat);

        cubit.attachPresenceUi();
        cubit.syncPresenceTeam(_team);
        cubit.updateTarget(_target(shell));
        _settleUntil(
          async,
          () => refreshes >= 1 &&
              wired.projection.availabilityFor(_seat) ==
                  AgentPresenceKind.working &&
              cubit.state.presence['m-lead']?.availability ==
                  MemberAvailability.working,
        );
        final refreshesAfterInitial = refreshes;
        expect(
          refreshesAfterInitial,
          greaterThan(0),
          reason: 'the initial value must reach the projection before '
              'disconnect/reconnect assertions',
        );

        service.result = {'m-lead': _disconnected};
        cubit.tickFromIdleWatch();
        _settleUntil(
          async,
          () => cubit.state.presence['m-lead']?.connection ==
                  MemberConnection.offline &&
              wired.projection.availabilityFor(_seat) == null,
        );

        service.result = {'m-lead': _connectedWorking};
        cubit.tickFromIdleWatch();
        _settleUntil(
          async,
          () => cubit.state.presence['m-lead']?.connection ==
                  MemberConnection.connected &&
              wired.projection.availabilityFor(_seat) ==
                  AgentPresenceKind.working,
        );

        // Disconnect tombstoned the seat; reconnect republishes working even
        // though the kind matches the pre-disconnect value — both are
        // projection changes, so `changes` fires twice more.
        expect(wired.dispatcher.handledCounts['AgentPresenceKind.working'], 2);
        expect(wired.dispatcher.handledCounts['AgentPresenceKind.cleared'], 1);
        expect(
          refreshes,
          greaterThan(refreshesAfterInitial),
          reason: 'cleared tombstone and working re-set both notify listeners',
        );
        expect(
          cubit.state.presence['m-lead']?.availability,
          MemberAvailability.working,
        );
        expect(
          cubit.state.presence['m-lead']?.connection,
          MemberConnection.connected,
        );
        _stopDispatcher(async, wired.dispatcher);
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
        // Synchronous-path case: the sink feeds the projection in-line so the
        // teardown assertions (seat dropped, bridge disposed, sub cancelled)
        // are independent of the dispatcher hop this test does not exercise.
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
