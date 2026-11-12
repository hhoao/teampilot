import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_supervisor.dart';

import '../../support/post_frame_test_harness.dart' show waitUntil;

const _profile = SshProfile(
  id: 'home',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

class _Harness {
  _Harness() {
    gate = SshConnectionGate();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connectionGate: gate,
    );
    supervisor = SshHomeConnectivitySupervisor(
      factory: factory,
      events: events,
      profileResolver: (id) => id == _profile.id ? _profile : null,
      gate: gate,
    );
  }

  final events = SshConnectionEvents();
  late final SshConnectionGate gate;
  late final SshClientFactory factory;
  late final SshHomeConnectivitySupervisor supervisor;

  Future<void> dispose() async {
    await supervisor.dispose();
    await factory.close();
  }
}

/// Wires a supervisor whose dial resolves without a real SSH client, so a
/// successful switch can be driven in isolation. `dials` records every dial.
class _DialHarness {
  _DialHarness() {
    gate = SshConnectionGate();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connectionGate: gate,
    );
    late SshHomeConnectivitySupervisor s;
    s = SshHomeConnectivitySupervisor(
      factory: factory,
      events: events,
      profileResolver: (id) => id == _profile.id ? _profile : null,
      gate: gate,
      dialProfile: (profile) async {
        dials.add(profile.id);
        s.publish(SshHomeConnectivityState.up(profile.id));
      },
    );
    supervisor = s;
  }

  final events = SshConnectionEvents();
  final dials = <String>[];
  late final SshConnectionGate gate;
  late final SshClientFactory factory;
  late final SshHomeConnectivitySupervisor supervisor;

  Future<void> dispose() async {
    await supervisor.dispose();
    await factory.close();
  }
}

void main() {
  test('a successful reconnect clears any prior failure (invariant 3)', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    final states = <SshHomeConnectivityState>[];
    final sub = h.supervisor.changes.listen(states.add);
    addTearDown(sub.cancel);

    // A stale failure from an earlier wave.
    h.supervisor.noteNonRetryableClose(_profile.id, StateError('auth'));
    await waitUntil(() => states.isNotEmpty && !states.last.isUp);
    expect(states.last.phase, SshPhase.failed);
    // The coordinator's onReconnected hook is the real path into `up`. The
    // state value clears failure/errorDetail/attempt in that one emission.
    h.supervisor.noteReconnected(_profile.id);

    await waitUntil(() => states.last.isUp);
    expect(states.last.phase, SshPhase.up);
    expect(states.last.storageLive, isTrue);
    expect(states.last.failure, isNull);
  });

  test('activateHome persists retries only for the active home', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    h.supervisor.activateHome(_profile.id);
    expect(h.supervisor.shouldPersistRetry(_profile.id), isTrue);
    expect(h.supervisor.shouldPersistRetry('other'), isFalse);
  });

  test('profileEdited never publishes a failed phase', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    h.supervisor.activateHome(_profile.id);
    final phases = <SshPhase>[];
    final sub = h.supervisor.changesFor(_profile.id).listen(
      (s) => phases.add(s.phase),
    );
    addTearDown(sub.cancel);

    h.supervisor.profileEdited(_profile.id);
    await waitUntil(() => phases.isNotEmpty);
    expect(phases.where((p) => p == SshPhase.failed), isEmpty);
  });

  test('a single dial completes and converges on up', () async {
    final h = _DialHarness();
    addTearDown(h.dispose);

    final states = <SshHomeConnectivityState>[];
    final sub = h.supervisor.changes.listen(states.add);
    addTearDown(sub.cancel);

    // Regression: an expression-bodied `whenComplete(() => map.remove(id))`
    // returned the in-flight Future and deadlocked `userConnect` forever.
    await h.supervisor
        .userConnect(_profile)
        .timeout(const Duration(seconds: 5));

    await waitUntil(() => states.any((s) => s.isUp));
    expect(h.dials, [_profile.id]);
    expect(states.last.phase, SshPhase.up);
    expect(states.last.storageLive, isTrue);
    expect(states.last.failure, isNull);
  });

  test('re-dialing after a failure stays up with no spurious down phase',
      () async {
    final h = _DialHarness();
    addTearDown(h.dispose);

    final states = <SshHomeConnectivityState>[];
    final sub = h.supervisor.changes.listen(states.add);
    addTearDown(sub.cancel);

    // The original bug: switching to a working connection reached the app but
    // a stale failure kept the "需要重新连接" banner / retry page alive.
    h.supervisor.noteNonRetryableClose(_profile.id, StateError('auth'));
    await waitUntil(() => states.isNotEmpty && !states.last.isUp);

    await h.supervisor
        .userConnect(_profile)
        .timeout(const Duration(seconds: 5));
    await waitUntil(() => states.last.isUp);
    final upIndex = states.lastIndexWhere((s) => s.isUp);

    // No real transport close happened, so nothing after `up` may regress to
    // a down/reconnecting phase, and the failure must be cleared atomically.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(states.last.isUp, isTrue);
    expect(states.last.failure, isNull);
    expect(
      states.skip(upIndex).where((s) => s.isDown || s.retryActive),
      isEmpty,
    );
  });

  test('concurrent dials share one in-flight attempt', () async {
    final h = _DialHarness();
    addTearDown(h.dispose);

    await Future.wait([
      h.supervisor.userConnect(_profile),
      h.supervisor.userConnect(_profile),
    ]).timeout(const Duration(seconds: 5));

    expect(h.dials, [_profile.id]);
    expect(h.supervisor.stateFor(_profile.id).isUp, isTrue);
  });
}
