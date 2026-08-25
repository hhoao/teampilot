import 'dart:async';

import 'runtime_event.dart';

final class SeatEventStream {
  final StreamController<RuntimeEventEnvelope> _events =
      StreamController<RuntimeEventEnvelope>.broadcast(sync: true);

  Stream<RuntimeEventEnvelope> eventsFor(RuntimeSeatKey seat) =>
      _events.stream.where((event) => event.seat == seat);

  void publish(RuntimeEventEnvelope event) => _events.add(event);

  Future<void> close() => _events.close();
}
