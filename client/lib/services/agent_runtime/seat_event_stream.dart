import 'dart:async';

import 'runtime_event.dart';

final class SeatEventStream {
  final StreamController<RuntimeEventEnvelope> _events =
      StreamController<RuntimeEventEnvelope>.broadcast(sync: true);

  /// Every seat's events (composition-level subscribers such as the
  /// prompt-delivery coordinator join here).
  Stream<RuntimeEventEnvelope> get events => _events.stream;

  Stream<RuntimeEventEnvelope> eventsFor(RuntimeSeatKey seat) =>
      _events.stream.where((event) => event.seat == seat);

  void publish(RuntimeEventEnvelope event) => _events.add(event);

  Future<void> close() => _events.close();
}
