import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/endpoint_dial_planner.dart';

SshProfile pairedProfile(List<SshReachabilityEndpoint> endpoints) =>
    const SshProfile(
      id: 'paired',
      name: 'Alice desktop',
      host: '192.168.1.20',
      username: 'alice',
      pairedDesktopId: 'AbCdEf0123_-xyZ9',
    ).copyWith(endpoints: endpoints);

const lanA = SshReachabilityEndpoint(
  kind: SshEndpointKind.lan,
  host: '192.168.1.20',
  port: 22,
);
const extraA = SshReachabilityEndpoint(
  kind: SshEndpointKind.extra,
  host: 'desktop.example.test',
  port: 2222,
);
const relayA = SshReachabilityEndpoint(
  kind: SshEndpointKind.relay,
  host: 'relay.example.test',
  port: 443,
);

class _Harness {
  final dialed = <SshReachabilityEndpoint>[];
  final saved = <SshProfile>[];

  late final PairedConnectAttempt attempt = PairedConnectAttempt(
    saveLastGood: (updated) async => saved.add(updated),
    openRelayTunnel: openRelayTunnel,
  );

  Future<({InternetAddress address, int port})> Function(
    SshProfile,
    SshReachabilityEndpoint,
  )? openRelayTunnel;
}

void main() {
  test('falls through a network failure and persists the winning endpoint',
      () async {
    final harness = _Harness();

    final winner = await harness.attempt.connectFirst(
      profile: pairedProfile(const [lanA, extraA]),
      dial: (endpoint) async {
        harness.dialed.add(endpoint);
        if (endpoint == lanA) {
          throw const SocketException('LAN unreachable');
        }
      },
    );

    expect(winner, extraA);
    expect(harness.dialed, const [lanA, extraA]);
    expect(harness.saved.single.host, 'desktop.example.test');
    expect(harness.saved.single.port, 2222);
    expect(harness.saved.single.lastGoodKind, SshEndpointKind.extra);
  });

  test('a host-key mismatch aborts the whole attempt without fallthrough',
      () async {
    final harness = _Harness();

    await expectLater(
      harness.attempt.connectFirst(
        profile: pairedProfile(const [lanA, extraA]),
        dial: (endpoint) async {
          harness.dialed.add(endpoint);
          throw SshHostKeyMismatch(endpoint);
        },
      ),
      throwsA(isA<SshHostKeyMismatch>()),
    );
    expect(harness.dialed, const [lanA]);
    expect(harness.saved, isEmpty);
  });

  test('maps dartssh2 host-key rejection to an attempt abort', () async {
    final harness = _Harness();

    await expectLater(
      harness.attempt.connectFirst(
        profile: pairedProfile(const [lanA, extraA]),
        dial: (endpoint) async {
          harness.dialed.add(endpoint);
          throw SSHAuthAbortError('handshake failed', SSHHostkeyError('bad'));
        },
      ),
      throwsA(isA<SshHostKeyMismatch>()),
    );
    expect(harness.dialed, const [lanA]);
    expect(harness.saved, isEmpty);
  });

  test('a relay win persists only lastGoodKind and never rewrites the host',
      () async {
    final harness = _Harness()
      ..openRelayTunnel = (profile, endpoint) async {
        return (address: InternetAddress.loopbackIPv4, port: 45678);
      };

    final winner = await harness.attempt.connectFirst(
      profile: pairedProfile(const [relayA]),
      dial: (endpoint) async => harness.dialed.add(endpoint),
    );

    expect(winner.kind, SshEndpointKind.relay);
    expect(harness.dialed, const [relayA]);
    expect(harness.saved.single.host, '192.168.1.20');
    expect(harness.saved.single.lastGoodKind, SshEndpointKind.relay);
  });

  test('skips relay candidates when no tunnel opener is available', () async {
    final harness = _Harness();

    final winner = await harness.attempt.connectFirst(
      profile: pairedProfile(const [lanA, relayA]),
      dial: (endpoint) async => harness.dialed.add(endpoint),
    );

    expect(winner, lanA);
    expect(harness.dialed, const [lanA]);
  });

  test('rethrows the last failure when every candidate fails', () async {
    final harness = _Harness();

    await expectLater(
      harness.attempt.connectFirst(
        profile: pairedProfile(const [lanA, extraA]),
        dial: (endpoint) async {
          harness.dialed.add(endpoint);
          throw const SocketException('down');
        },
      ),
      throwsA(isA<SocketException>()),
    );
    expect(harness.saved, isEmpty);
  });

  test('a hung dial falls through after the per-endpoint timeout', () async {
    final harness = _Harness();

    final winner = await harness.attempt.connectFirst(
      profile: pairedProfile(const [lanA, extraA]),
      perEndpointTimeout: const Duration(milliseconds: 40),
      dial: (endpoint) async {
        harness.dialed.add(endpoint);
        if (endpoint == lanA) {
          await Completer<void>().future;
        }
      },
    );

    expect(winner, extraA);
    expect(harness.saved.single.lastGoodKind, SshEndpointKind.extra);
  });
}
