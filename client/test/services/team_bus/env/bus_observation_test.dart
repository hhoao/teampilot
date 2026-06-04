import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/env/bus_environment.dart';
import 'package:teampilot/services/team_bus/env/bus_event_sink.dart';
import 'package:teampilot/services/team_bus/env/bus_observation.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import '../support/fake_member_launcher.dart';

class _CapturingSink implements BusEventSink {
  final List<BusObservation> events = [];
  @override
  void emit(BusObservation o) => events.add(o);
  List<T> ofType<T>() => events.whereType<T>().toList();
}

void main() {
  late _CapturingSink sink;
  late TeamBus bus;

  TeamBus build() => TeamBus(
        launcher: FakeMemberLauncher(),
        environment: BusEnvironment(
          ids: () => 'fixed-id',
          clock: () => 0,
          events: sink,
        ),
      );

  setUp(() {
    sink = _CapturingSink();
    bus = build();
  });

  test('routing a message emits MessageRouted', () async {
    bus.declareMember(AgentNode.test(
      memberId: 'w',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    await bus.send(
      const TeamMessage(id: '1', from: 'lead', to: 'w', content: 'hi'),
    );
    final routed = sink.ofType<MessageRouted>().single;
    expect(routed.to, 'w');
    expect(routed.from, 'lead');
  });

  test('over-hop and unknown-member sends emit MessageDropped', () async {
    await bus.send(
      const TeamMessage(id: '1', from: 'a', to: 'ghost', content: 'x', hop: 99),
    );
    await bus.send(
      const TeamMessage(id: '2', from: 'a', to: 'ghost', content: 'x'),
    );
    final dropped = sink.ofType<MessageDropped>();
    expect(dropped, hasLength(2));
    expect(dropped.first.reason, contains('over-hop'));
    expect(dropped.last.reason, 'unknown-member');
  });

  test('take → rollback → confirm emit the delivery lifecycle', () async {
    final node = AgentNode.test(
      memberId: 'w',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);
    node.inbox.deliver(
      const TeamMessage(id: '1', from: 'l', to: 'w', content: 'hi'),
    );

    final batch = await bus.receivePending('w');
    expect(sink.ofType<BatchTaken>().single.count, 1);

    bus.redeliver('w', batch);
    expect(sink.ofType<DeliveryRolledBack>().single.count, 1);

    await bus.receivePending('w');
    await bus.acknowledgeDelivery('w', ['1']);
    expect(sink.ofType<DeliveryConfirmed>().single.count, 1);
  });
}
