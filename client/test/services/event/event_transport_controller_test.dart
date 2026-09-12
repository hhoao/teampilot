import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/event_transport_client.dart';
import 'package:teampilot/services/event/event_transport_controller.dart';

final class _FakeEndpoint implements EventTransportEndpoint {
  _FakeEndpoint(this.label, this.log);

  final String label;
  final List<String> log;

  @override
  Future<void> start() async => log.add('$label.start');

  @override
  Future<void> stop() async => log.add('$label.stop');
}

final class _FakeChannel implements EventTransportByteChannel {
  @override
  Stream<List<int>> get incoming => const Stream.empty();

  @override
  void add(List<int> data) {}

  @override
  Future<void> close() async {}
}

void main() {
  late List<String> log;
  late EventTransportController controller;

  setUp(() {
    log = <String>[];
    controller = EventTransportController(
      createServer: () => _FakeEndpoint('server', log),
      createClient: ({required open}) => _FakeEndpoint('client', log),
    );
  });

  tearDown(() async {
    await controller.apply(EventTransportRole.none);
  });

  test('apply server then client stops server before starting client', () async {
    await controller.apply(EventTransportRole.server);
    await controller.apply(
      EventTransportRole.client,
      open: () async => _FakeChannel(),
    );

    expect(log, ['server.start', 'server.stop', 'client.start']);
  });

  test('apply is idempotent for the same role', () async {
    await controller.apply(EventTransportRole.server);
    await controller.apply(EventTransportRole.server);
    await controller.apply(EventTransportRole.server);

    expect(log, ['server.start']);
  });

  test('apply none stops the active endpoint', () async {
    await controller.apply(EventTransportRole.server);
    await controller.apply(EventTransportRole.none);

    expect(log, ['server.start', 'server.stop']);
  });
}
