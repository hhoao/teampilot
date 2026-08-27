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
const lanB = SshReachabilityEndpoint(
  kind: SshEndpointKind.lan,
  host: '192.168.1.21',
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

void main() {
  test('plans lan then extra then relay, keeping order within each kind', () {
    final plan = planEndpointDials(
      pairedProfile(const [relayA, extraA, lanB, lanA]),
    );

    // Offer order wins inside each kind: lanB was offered before lanA.
    expect(plan, const [lanB, lanA, extraA, relayA]);
  });

  test('drops unknown-reachability duplicates of nothing but keeps all kinds', () {
    // Same candidate listed twice must stay twice: the phone dials each.
    final plan = planEndpointDials(pairedProfile(const [lanA, lanA]));

    expect(plan, const [lanA, lanA]);
  });

  test('lanOnly policy drops extra and relay candidates', () {
    final plan = planEndpointDials(
      pairedProfile(const [relayA, extraA, lanA]),
      policy: ConnectPolicy.lanOnly,
    );

    expect(plan, const [lanA]);
  });

  test('profiles without endpoints plan nothing', () {
    expect(planEndpointDials(pairedProfile(const [])), isEmpty);
  });
}
