import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection/device_connection.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/models/connection/ssh_plan.dart';
import 'package:teampilot/models/ssh_auth_type.dart';
import 'package:teampilot/models/ssh_reachability.dart';

import '../support/connection_fixtures.dart';

const _lan = SshReachabilityEndpoint(
  kind: SshEndpointKind.lan,
  host: '10.0.0.5',
  port: 2222,
);
const _relay = SshReachabilityEndpoint(
  kind: SshEndpointKind.extra,
  host: '203.0.113.9',
  port: 22,
);

void main() {
  test('round-trips every field', () {
    final connection = deviceConnection(
      machineId: 't1',
      displayName: 'dev-box',
      username: 'alice',
      authType: SshAuthType.privateKey,
      endpoints: const [_lan, _relay],
      preferredKind: SshEndpointKind.extra,
      credentialRef: 'v1',
      paths: const HomePathCache(home: '/home/alice', appDataRoot: '/data'),
      pairedDesktopId: 'd1',
      embeddedTarget: true,
      relayUrl: 'wss://relay',
      fingerprints: const ['SHA256:abc'],
      updatedAt: 42,
    );

    final restored = DeviceConnection.fromJson(connection.toJson());

    expect(restored, connection);
    expect(restored.primaryEndpoint, _relay);
    expect(restored.generation, connection.generation);
    expect(restored.plan.credentialRef, 'v1');
    expect(restored.plan.embeddedTarget, isTrue);
    expect(restored.plan.relayUrl, 'wss://relay');
  });

  test('primary endpoint follows the preference, else the first endpoint', () {
    final preferred = deviceConnection(
      endpoints: const [_lan, _relay],
      preferredKind: SshEndpointKind.extra,
    );
    expect(preferred.primaryEndpoint, _relay);

    final noPreference = deviceConnection(endpoints: const [_relay, _lan]);
    expect(noPreference.primaryEndpoint, _relay);
  });

  test('generation ignores address order, preference and credential ref', () {
    final a = deviceConnection(
      endpoints: const [_lan, _relay],
      preferredKind: SshEndpointKind.lan,
      credentialRef: 'vault-a',
    );
    final b = deviceConnection(
      endpoints: const [_relay, _lan],
      preferredKind: SshEndpointKind.extra,
      credentialRef: 'vault-b',
      displayName: 'renamed',
    );

    expect(b.plan.generation, a.plan.generation);
    expect(
      b.generation,
      a.generation,
      reason: 'rotating a secret or a display name must not drain a lease',
    );
  });

  test('generation changes with the address set, account or trust policy', () {
    final base = deviceConnection(endpoints: const [_lan]);

    final moved = deviceConnection(
      endpoints: const [
        SshReachabilityEndpoint(kind: SshEndpointKind.lan, host: 'h2', port: 22),
      ],
    );
    final otherUser = deviceConnection(username: 'other');
    final repinned = deviceConnection(fingerprints: const ['SHA256:new']);

    expect(moved.generation, isNot(base.generation));
    expect(otherUser.generation, isNot(base.generation));
    expect(repinned.generation, isNot(base.generation));
  });

  test('a plan requires at least one endpoint', () {
    expect(
      () => SshPlan(
        machineId: const MachineId('m1'),
        username: 'u',
        endpoints: const [],
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
