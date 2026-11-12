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
      connectionGate: gate, // Task 4 改成 ioGuard: gate.beforeIo（唯一一行变化）
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

void main() {
  test('observeProfile re-derives up and clears any prior failure', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    final states = <SshHomeConnectivityState>[];
    final sub = h.supervisor.changes.listen(states.add);
    addTearDown(sub.cancel);

    // A stale failure from an earlier wave.
    h.supervisor.noteNonRetryableClose(_profile.id, StateError('auth'));
    // Gate has no onUp callback (see D3), so observeProfile is the explicit
    // re-derive trigger. It always emits once, even when already subscribed.
    h.gate.markUp(_profile.id);
    h.supervisor.observeProfile(_profile.id);

    await waitUntil(() => states.isNotEmpty && states.last.isUp);
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
}
